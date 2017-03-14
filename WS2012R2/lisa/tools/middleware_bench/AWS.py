"""
Linux on Hyper-V and Azure Test Code, ver. 1.0.0
Copyright (c) Microsoft Corporation

All rights reserved
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the Apache Version 2.0 License for specific language governing
permissions and limitations under the License.
"""

import os
import time
import logging
import constants

from boto import ec2
from boto import vpc
from boto.manage.cmdshell import sshclient_from_instance

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class AWSConnector:
    """
    AWS EC2 connector that uses boto plugin.
    """
    def __init__(self, keyid=None, secret=None, imageid=None, instancetype=None, user=None,
                 localpath=None, region=None, zone=None):
        """
        Init AWS connector to create and configure AWS ec2 instances.
        :param keyid: user key for executing remote connection
            http://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html
        :param secret: user secret for executing remote connection
        :param imageid: AMI image id from EC2 repo
        :param instancetype: instance flavor constituting resources
        :param user: remote ssh user for the instance
        :param localpath: localpath where the logs should be downloaded, and the
                            default path for other necessary tools
        :param region: EC2 region to connect to
        :param zone: EC2 zone where other resources should be available
        """
        self.keyid = keyid
        self.secret = secret
        self.imageid = imageid
        self.instancetype = instancetype
        self.user = user
        self.localpath = localpath
        if not region:
            self.region = 'eu-west-1'
        else:
            self.region = region
        if not zone:
            self.zone = self.region + 'a'
        else:
            self.zone = zone
        self.volume_type = {'ssd_gp2': 'gp2',
                            'ssd_io1': 'io1'}

        self.key_name = 'test_ssh_key'
        self.group_name = 'test_sec_group'
        self.conn = None
        self.security_group = None
        self.vpc_conn = None
        self.vpc_zone = None
        self.subnet = None
        self.elastic_ips = []
        self.instances = []
        self.ebs_vols = []

    def ec2_connect(self, region=None):
        """
        Obtain the EC2 connector by authenticating. This also creates the
        keypair and security group for the instance.
        :param region: region to connect to (optional, defaults to eu-west1)
        """
        self.conn = ec2.connect_to_region(region or self.region, aws_access_key_id=self.keyid,
                                          aws_secret_access_key=self.secret)
        self.create_key_pair(self.conn)
        self.create_security_group(self.conn)

    def aws_create_instance(self, user_data=None):
        """
        Create an EC2 instance.
        :param user_data: routines to be executed upon spawning the instance
        :return: EC2Instance object
        """
        reservation = self.conn.run_instances(self.imageid, key_name=self.key_name,
                                              instance_type=self.instancetype, placement=self.zone,
                                              security_groups=[self.group_name],
                                              user_data=user_data)
        instance = reservation.instances[0]
        time.sleep(5)
        self.wait_for_state(instance, 'state', 'running')

        # artificial wait for public ip
        time.sleep(5)
        instance.update()
        log.info('Created instance: {}'.format(instance.__dict__))
        self.instances.append(instance)

        return instance

    def vpc_connect(self, region=None):
        """
        Obtain the VPC EC2 connector by authenticating. This also creates the
        keypair and security group for the instance.
        :param region: region to connect to (optional, defaults to eu-west1)
        """
        self.vpc_conn = vpc.connect_to_region(region or self.region, aws_access_key_id=self.keyid,
                                              aws_secret_access_key=self.secret)
        self.vpc_zone = self.vpc_conn.create_vpc('10.10.0.0/16')
        self.vpc_conn.modify_vpc_attribute(self.vpc_zone.id, enable_dns_support=True)
        self.vpc_conn.modify_vpc_attribute(self.vpc_zone.id, enable_dns_hostnames=True)
        gateway = self.vpc_conn.create_internet_gateway()
        self.vpc_conn.attach_internet_gateway(gateway.id, self.vpc_zone.id)
        route_table = self.vpc_conn.create_route_table(self.vpc_zone.id)
        self.subnet = self.vpc_conn.create_subnet(self.vpc_zone.id, '10.10.10.0/24',
                                                  availability_zone=self.zone)
        self.vpc_conn.associate_route_table(route_table.id, self.subnet.id)
        self.vpc_conn.create_route(route_table.id, '0.0.0.0/0', gateway.id)
        self.create_security_group(self.vpc_conn, vpc_id=self.vpc_zone.id)
        self.create_key_pair(self.vpc_conn)

    def aws_create_vpc_instance(self, user_data=None):
        """
        Create a VPC EC2 instance.
        :param user_data: routines to be executed upon spawning the instance
        :return: EC2Instance object
        """
        reservation = self.vpc_conn.run_instances(self.imageid, key_name=self.key_name,
                                                  instance_type=self.instancetype,
                                                  placement=self.zone,
                                                  security_group_ids=[self.security_group.id],
                                                  subnet_id=self.subnet.id, user_data=user_data)
        instance = reservation.instances[0]
        time.sleep(5)
        self.wait_for_state(instance, 'state', 'running')

        elastic_ip = self.vpc_conn.allocate_address(domain='vpc')
        self.vpc_conn.associate_address(instance_id=instance.id,
                                        allocation_id=elastic_ip.allocation_id)
        self.elastic_ips.append(elastic_ip)
        self.instances.append(instance)

        # artificial wait for ip
        time.sleep(5)
        instance.update()
        log.info('Created instance: {}'.format(instance.__dict__))

        return instance

    def create_key_pair(self, conn):
        """
        Creates and saves a default key pair.
        :param conn: EC2Connection
        """
        try:
            key_pair = conn.create_key_pair(self.key_name)
            key_pair.save(self.localpath)
        except conn.ResponseError as e:
            if e.code == 'InvalidKeyPair.Duplicate':
                log.error('KeyPair: {} already exists.'.format(self.key_name))
            else:
                raise

    def create_security_group(self, conn, vpc_id=None):
        """
        Creates a default security group without restrictions.
        :param conn: EC2Connection
        :param vpc_id: VPC id where to create the security group.
        """
        cidr = '0.0.0.0/0'
        try:
            group = conn.create_security_group(self.group_name, 'All access', vpc_id=vpc_id)
            self.security_group = group
            group.authorize(ip_protocol='tcp', from_port=0, to_port=65535, cidr_ip=cidr)
            group.authorize(ip_protocol='tcp', from_port=22, to_port=22, cidr_ip=cidr)
            group.authorize(ip_protocol='udp', from_port=0, to_port=65535, cidr_ip=cidr)
            group.authorize(ip_protocol='icmp', from_port=-1, to_port=-1, cidr_ip=cidr)
        except conn.ResponseError as e:
            if e.code == 'InvalidGroup.Duplicate':
                log.warning('Security Group: {} already exists.'.format(self.group_name))
            elif e.code == 'InvalidPermission.Duplicate':
                log.warning('Security Group: {} already authorized'.format(self.group_name))
            else:
                raise

    def attach_ebs_volume(self, instance, size=10, volume_type=None, iops=None, device=None):
        """
        Create and attach an EBS volume to a given instance.
        :param instance: Instance object to attach the volume to
        :param size: size in GB of the volume
        :param volume_type: volume type: gp2 - SSD, st1 - HDD, sc1 - cold HDD;
                            defaults to magnetic disk
        :param iops: IOPS to associate with this volume.
        :param device: device mount location, defaults to '/dev/sdx'
        :return: EBSVolume object
        """
        conn = self.conn or self.vpc_conn
        # Add EBS volume DONE
        ebs_vol = conn.create_volume(size, self.zone, volume_type=volume_type, iops=iops)
        self.wait_for_state(ebs_vol, 'status', 'available')
        if not device:
            device = '/dev/sdx'
        conn.attach_volume(ebs_vol.id, instance.id, device=device)
        self.ebs_vols.append(ebs_vol)
        return ebs_vol

    def enable_sr_iov(self, instance, ssh_client):
        """
        Enable SR-IOV for a given instance.
        :param instance: EC2Instance object
        :param ssh_client: SSHClient
        :return: SSHClient (needs to reconnect after reboot)
        """
        conn = self.conn or self.vpc_conn
        sriov_status = conn.get_instance_attribute(instance.id, 'sriovNetSupport')
        log.info('Enabling SR-IOV on {}'.format(instance.id))
        if not sriov_status and ssh_client:
            util_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client.put_file(os.path.join(util_path, 'tests', 'enable_sr_iov.sh'),
                                '/tmp/enable_sr_iov.sh')
            ssh_client.run('chmod +x /tmp/enable_sr_iov.sh')
            ssh_client.run("sed -i 's/\r//' /tmp/enable_sr_iov.sh")
            ssh_client.run('/tmp/enable_sr_iov.sh')
            conn.stop_instances(instance_ids=[instance.id])
            self.wait_for_state(instance, 'state', 'stopped')
            mod_sriov = conn.modify_instance_attribute(instance.id, 'sriovNetSupport', 'simple')
            log.info('Modifying SR-IOV state to simple: {}'.format(mod_sriov))
            conn.start_instances(instance_ids=[instance.id])
            self.wait_for_state(instance, 'state', 'running')

            client = self.wait_for_ping(instance)
            instance.update()
            sriov_status = conn.get_instance_attribute(instance.id, 'sriovNetSupport')
            log.info("SR-IOV status is: {}".format(sriov_status))
        return client

    @staticmethod
    def wait_for_state(obj, attr, state):
        """
        Check when an AWS object attribute state is achieved.
        :param obj: the AWS object to verify attribute status
        :param attr: object attribute to be verified
        :param state: attribute state to wait for
        :return:
        """
        log.info('Waiting for {} status {}'.format(str(obj), state))
        while getattr(obj, attr) != state:
            time.sleep(5)
            obj.update()

    def wait_for_ping(self, instance, user=None):
        """
        To obtain the SSH client, we must wait for the instance to boot,
        even the EC2 instance status is available.
        :param instance: created ec2 instance to wait for
        :param user: SSH user to use with the created key
        :return: SSHClient or None on error
        """
        host_key_file = os.path.join(self.localpath, 'known_hosts')
        ping_arg = '-n'
        if os.name == 'posix':
            ping_arg = '-c'
        if not instance.public_dns_name:
            log.error("Spawned instance was not allocated a public IP. Please try again.")
            raise
        ping_cmd = 'ping {} 1 {}'.format(ping_arg, instance.ip_address)
        try:
            timeout = 0
            while os.system(ping_cmd) != 0 or timeout >= 60:
                time.sleep(5)
                timeout += 5
            # artificial wait for ssh service up status
            time.sleep(30)
            open(host_key_file, 'w').close()
            client = sshclient_from_instance(instance, os.path.join(self.localpath,
                                                                    self.key_name + '.pem'),
                                             host_key_file=host_key_file,
                                             user_name=user or self.user)
        except Exception as e:
            log.error(e)
            client = None
        return client

    def teardown(self, instance=None, device=None):
        """
        Cleanup created instances and devices.
        :param instance: EC2Instance object
        :param device: EBS device mount location
        """
        log.info("Running teardown.")
        conn = self.conn or self.vpc_conn
        if not instance:
            conn.terminate_instances(instance_ids=[i.id for i in self.instances])
        else:
            conn.terminate_instances(instance_ids=[instance.id])

        for inst in self.instances:
            self.wait_for_state(inst, 'state', 'terminated')

        if self.ebs_vols:
            for vol in self.ebs_vols:
                for inst in self.instances:
                    try:
                        if not device:
                            conn.detach_volume(vol.id, inst.id, device=constants.DEVICE_AWS)
                    except Exception as e:
                        log.info(e)
                    self.wait_for_state(vol, 'status', 'available')
                    # time.sleep(30)
                    try:
                        conn.delete_volume(vol.id)
                    except Exception as e:
                        log.info(e)

        if self.vpc_zone:
            for eip in self.elastic_ips:
                self.vpc_conn.release_address(allocation_id=eip.allocation_id)

            subnets = self.vpc_conn.get_all_subnets(filters={'vpcId': self.vpc_zone.id})
            for subnet in subnets:
                self.vpc_conn.delete_subnet(subnet.id)

            try:
                security_group = self.vpc_conn.get_all_security_groups(
                        filters={'vpc-id': self.vpc_zone.id})
                for sg in security_group:
                    if sg.name == self.group_name:
                        self.vpc_conn.delete_security_group(group_id=sg.id)
            except Exception as e:
                log.info(e)

            route_tables = self.vpc_conn.get_all_route_tables(filters={'vpc-id': self.vpc_zone.id})
            for route_table in route_tables:
                try:
                    self.vpc_conn.delete_route(route_table.id, '10.10.0.0/16')
                    log.info('deleted 10.10.0.0 route from table {}'.format(route_table.id))
                except Exception as e:
                    log.info(e)
                try:
                    self.vpc_conn.delete_route(route_table.id, '0.0.0.0/0')
                    log.info('deleted 0.0.0.0 route from table {}'.format(route_table.id))
                except Exception as e:
                    log.info(e)
                try:
                    self.vpc_conn.delete_route_table(route_table.id)
                    log.info('deleted route table {}'.format(route_table.id))
                except Exception as e:
                    log.info(e)

            try:
                internet_gateways = self.vpc_conn.get_all_internet_gateways(
                    filters={'attachment.vpc-id': self.vpc_zone.id})
                for internet_gateway in internet_gateways:
                    self.vpc_conn.detach_internet_gateway(internet_gateway.id, self.vpc_zone.id)
                    self.vpc_conn.delete_internet_gateway(internet_gateway.id)
            except Exception as e:
                log.info(e)

            self.vpc_conn.delete_vpc(vpc_id=self.vpc_zone.id)
            self.vpc_zone = None
