/*
 * An implementation of key value pair (KVP) functionality for Linux.
 *
 * Copyright (c) 2011, Microsoft Corporation.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 * Place - Suite 330, Boston, MA 02111-1307 USA.
 *
 * Authors:
 * 	K. Y. Srinivasan <kys@microsoft.com>
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include <sys/utsname.h>
#include <linux/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
//#include <linux/connector.h>
//#include "../include/linux/hyperv.h"
#include <linux/netlink.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <syslog.h>
#include <sys/stat.h>
#include <fcntl.h>

#define HV_KVP_EXCHANGE_MAX_KEY_SIZE     512
#define HV_KVP_EXCHANGE_MAX_VALUE_SIZE  2048

struct kvp_record {
	__u8 key[HV_KVP_EXCHANGE_MAX_KEY_SIZE];
	__u8 value[HV_KVP_EXCHANGE_MAX_VALUE_SIZE];
};


static void kvp_acquire_lock(int fd)
{
	struct flock fl = {F_RDLCK, SEEK_SET, 0, 0, 0};
	fl.l_pid = getpid();

	if (fcntl(fd, F_SETLKW, &fl) == -1) {
		perror("fcntl lock");
		exit(-1);
	}
}

static void kvp_release_lock(int fd)
{
	struct flock fl = {F_UNLCK, SEEK_SET, 0, 0, 0};
	fl.l_pid = getpid();

	if (fcntl(fd, F_SETLK, &fl) == -1) {
		perror("fcntl unlock");
		exit(-1);
	}
}

/*
 * Retrieve the records from a specific pool.
 *
 * pool: specific pool to extract the records from.
 * buffer: Client allocated memory for reading the records to.
 * num_records: On entry specifies the size of the buffer; on exit this will
 * have the number of records retrieved.
 * more_records: set to non-zero to indicate that there are more records in the pool
 * than could be retrieved. This indicates that the buffer was too small to
 * retrieve all the records.
 */

int kvp_read_records(int pool, struct kvp_record *buffer, int *num_records,
			int *more_records)
{
	int  fd;
	int  error = 0;
	FILE *filep;
	size_t records_read;
	__u8 fname[50];

	sprintf(fname, "/var/lib/hyperv/.kvp_pool_%d", pool);
	fd = open(fname, S_IRUSR);

	if (fd == -1) {
		perror("Open failed");
		return 1;
	}

	filep = fopen(fname, "r");
	if (!filep) {
		close (fd);
		perror("fopen failed");
		return 1;	
	}

	kvp_acquire_lock(fd);
	records_read = fread(buffer, sizeof(struct kvp_record),
					*num_records,
					filep);
	kvp_release_lock(fd);

	if (ferror(filep)) {
		error = 1;
		goto done;
	}
	if (!feof(filep))
		*more_records = 1;

	*num_records = records_read;

done:
	close (fd);
	fclose(filep);
	return error;
}

/*
 * Append a  record to a specific pool.
 *
 * pool: specific pool to append the record to.
 *
 * key: key in the record
 * key_size: size of the key
 *
 * value: value in the record
 * value_size: size of the value string
 */

int kvp_append_record(int pool, __u8 *key, int key_size, 
			__u8 *value, int value_size)
{
	int  fd;
	FILE *filep;
	__u8 fname[50];
	struct kvp_record write_buffer;

	memcpy(write_buffer.key, key, key_size);
	memcpy(write_buffer.value, value, value_size);

	sprintf(fname, "/var/lib/hyperv/.kvp_pool_%d", pool);
	fd = open(fname, S_IRUSR);

	if (fd == -1) {
		perror("Open failed");
		return 1;
	}

	filep = fopen(fname, "a");
	if (!filep) {
		close (fd);
		perror("fopen failed");
		return 1;
	}

	kvp_acquire_lock(fd);
	fwrite(&write_buffer, sizeof(struct kvp_record),
				1, filep);
	kvp_release_lock(fd);

	close (fd);
	fclose(filep);
	return 0;
}

/*
 * Delete a record from a specific pool.
 *
 * pool: specific pool to delete the record from.
 * key: key in the record
 *
 */

int kvp_delete_record(int pool, __u8 *key)
{
	int  fd;
	FILE *filep;
	__u8 fname[50];

	int i;
	int more;
	int num_records = 200;
	struct kvp_record my_records[200]; 

	if (kvp_key_exists(pool, key) != 0)  {
		return 0;
	}

	if (kvp_read_records(pool, my_records, &num_records, &more)) {
		printf("kvp_read_records failed\n");
		exit(-1);
	}

	sprintf(fname, "/var/lib/hyperv/.kvp_pool_%d", pool);
	fd = open(fname, S_IRUSR);
	if (fd == -1) {
		perror("Open failed");
		return 1;
	}

	kvp_acquire_lock(fd);
	filep = fopen(fname, "w");
	if (!filep) {
		close (fd);
		perror("fopen failed");
		return 1;
	}
	kvp_release_lock(fd);

	close (fd);
	fclose(filep);

	for (i = 0; i < num_records; i++) {
		if (strcmp(my_records[i].key, key) != 0) {
			kvp_append_record(pool, my_records[i].key, strlen(my_records[i].key),
				my_records[i].value, strlen(my_records[i].value));
		}
	}
	/* Fixme: should check "more" and append additional if needed */

	return 0;
}

/*
 * Confirm a record exists in a specific pool.
 *
 * pool: specific pool to delete the record from.
 * key: key in the record
 *
 */

int kvp_key_exists(int pool, __u8 *key)
{
	int i;
	int more;
	int num_records = 200;
	struct kvp_record my_records[200];

	if (kvp_read_records(pool, my_records, &num_records, &more)) {
		printf("kvp_read_records failed\n");
		exit(-1);
	}
	for (i = 0; i < num_records; i++) {
		if (strcmp(my_records[i].key, key) == 0) {
			return 0;
		}
	}
	/* Fixme: should check "more" */

	return 1;
}

struct kvp_record my_records[200]; 
main(int argc, char *argv[])
{
	int error;
	int more;
	int i, j;
	int num_records = 200;
	int pool = 0;
	char *key, *value;

	if (argc > 1 && strcmp(argv[1], "append") == 0) { /* Append a key-value */
		if (argc < 5) {
			printf("Usage: %s append <pool> <key> <value>\n", argv[0]);
			exit(0);
		}
		pool = atoi(argv[2]);
		key = argv[3];
		value = argv[4];
		if (kvp_key_exists(pool, key) == 0) {
			kvp_delete_record(pool, key);
		}
		if (kvp_append_record(pool, key, strlen(key)+1,
					value, strlen(value)+1) != 0)  {
			printf("Error: kvp_append_record() returned non-zero\n");
		}
	}

	else  {
		for (i = 0; i < 5; i++) {
			if (argc > 1) {
				pool = atoi(argv[1]);
				if (i != pool) {
					continue;
				}
			}

			num_records = 200;
			if (kvp_read_records(i, my_records, &num_records, &more)) {
				printf("kvp_read_records failed\n");
				exit(-1);
			}
			printf("Pool is %d\n", i);
			printf("Num records is %d\n", num_records);
			if (more)
				printf("More records available\n");
			for (j = 0; j < num_records; j++)
				printf("Key: %s; Value: %s\n", my_records[j].key, my_records[j].value);
		}
	}
}
