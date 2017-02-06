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
import paramiko
import socket


class SSHClient(object):
    """
    This class creates a paramiko.SSHClient() object that represents
    a session with an SSH server. You can use the SSHClient object to send
    commands to the remote host and manipulate files on the remote host.

    :param server: A server hostname or ip.
    :param host_key_file: The path to the user's .ssh key files.
    :param user: The username for the SSH connection. Default = 'root'.
    :param timeout: The optional timeout variable for the TCP connection.
    :param ssh_pwd: An optional password to use for authentication or for
                    unlocking the private key.
    :param ssh_key_file: SSH key pem data
    """

    def __init__(self, server, host_key_file='~/.ssh/known_hosts', user='root', timeout=None,
                 ssh_pwd=None, ssh_key_file=None):
        self.server = server
        self.host_key_file = host_key_file
        self.user = user
        self._timeout = timeout
        self._pkey = paramiko.RSAKey.from_private_key_file(ssh_key_file, password=ssh_pwd)
        self._ssh_client = paramiko.SSHClient()
        self._ssh_client.load_system_host_keys()
        self._ssh_client.load_host_keys(os.path.expanduser(host_key_file))
        self._ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.connect()

    def connect(self, num_retries=5):
        """
        Connect to an SSH server and authenticate with it.
        :type num_retries: int
        :param num_retries: The maximum number of connection attempts.
        """
        retry = 0
        while retry < num_retries:
            try:
                self._ssh_client.connect(self.server,
                                         username=self.user,
                                         pkey=self._pkey,
                                         timeout=self._timeout)
                return
            except socket.error as xxx_todo_changeme:
                (value, message) = xxx_todo_changeme.args
                if value in (51, 61, 111):
                    print('SSH Connection refused, will retry in 5 seconds')
                    time.sleep(5)
                    retry += 1
                else:
                    raise
            except paramiko.BadHostKeyException:
                print("{} has an entry in ~/.ssh/known_hosts and it doesn't match".format(
                        self.server))
                print('Edit that file to remove the entry and then hit return to try again')
                raw_input('Hit Enter when ready')
                retry += 1
            except EOFError:
                print('Unexpected Error from SSH Connection, retry in 5 seconds')
                time.sleep(5)
                retry += 1
        print('Could not establish SSH connection')

    def open_sftp(self):
        """
        Open an SFTP session on the SSH server.
        :rtype: :class:`paramiko.sftp_client.SFTPClient`
        :return: An SFTP client object.
        """
        return self._ssh_client.open_sftp()

    def get_file(self, src, dst):
        """
        Open an SFTP session on the remote host, and copy a file from
        the remote host to the specified path on the local host.
        :type src: string
        :param src: The path to the target file on the remote host.

        :type dst: string
        :param dst: The path on your local host where you want to
                    store the file.
        """
        sftp_client = self.open_sftp()
        sftp_client.get(src, dst)

    def put_file(self, src, dst):
        """
        Open an SFTP session on the remote host, and copy a file from
        the local host to the specified path on the remote host.
        :type src: string
        :param src: The path to the target file on your local host.

        :type dst: string
        :param dst: The path on the remote host where you want to store
                    the file.
        """
        sftp_client = self.open_sftp()
        sftp_client.put(src, dst)

    def open(self, filename, mode='r', bufsize=-1):
        """
        Open an SFTP session to the remote host, and open a file on
        that host.
        :type filename: string
        :param filename: The path to the file on the remote host.

        :type mode: string
        :param mode: The file interaction mode.

        :type bufsize: integer
        :param bufsize: The file buffer size.

        :rtype: :class:`paramiko.sftp_file.SFTPFile`
        :return: A paramiko proxy object for a file on the remote server.
        """
        sftp_client = self.open_sftp()
        return sftp_client.open(filename, mode, bufsize)

    def listdir(self, path):
        """
        List all of the files and subdirectories at the specified path
        on the remote host.

        :type path: string
        :param path: The base path from which to obtain the list.

        :rtype: list
        :return: A list of files and subdirectories at the specified path.
        """
        sftp_client = self.open_sftp()
        return sftp_client.listdir(path)

    def isdir(self, path):
        """
        Check the specified path on the remote host to determine if
        it is a directory.

        :type path: string
        :param path: The path to the directory that you want to check.

        :rtype: integer
        :return: If the path is a directory, the function returns 1.
                If the path is a file or an invalid path, the function
                returns 0.
        """
        status = self.run('[ -d %s ] || echo "FALSE"' % path)
        if status[1].startswith('FALSE'):
            return 0
        return 1

    def exists(self, path):
        """
        Check the remote host for the specified path, or a file
        at the specified path. This function returns 1 if the
        path or the file exist on the remote host, and returns 0 if
        the path or the file does not exist on the remote host.
        :type path: string
        :param path: The path to the directory or file that you want to check.

        :rtype: integer
        :return: If the path or the file exist, the function returns 1.
                If the path or the file do not exist on the remote host,
                the function returns 0.
        """
        status = self.run('[ -a %s ] || echo "FALSE"' % path)
        if status[1].startswith('FALSE'):
            return 0
        return 1

    def run(self, command):
        """
        Run a command on the remote host.

        :type command: string
        :param command: The command that you want to send to the remote host.

        :rtype: tuple
        :return: This function returns a tuple that contains an integer status,
                the stdout from the command, and the stderr from the command.

        """
        status = 0
        t = []
        try:
            t = self._ssh_client.exec_command(command)
        except paramiko.SSHException:
            status = 1
        std_out = t[1].read()
        std_err = t[2].read()
        t[0].close()
        t[1].close()
        t[2].close()
        return status, std_out, std_err

    def run_pty(self, command):
        """
        Request a pseudo-terminal from a server, and execute a command on that
        server.
        :type command: string
        :param command: The command that you want to run on the remote host.

        :rtype: :class:`paramiko.channel.Channel`
        :return: An open channel object.
        """
        channel = self._ssh_client.get_transport().open_session()
        channel.get_pty()
        channel.exec_command(command)
        return channel

    def close(self):
        """
        Close an SSH session and any open channels that are tied to it.
        """
        transport = self._ssh_client.get_transport()
        transport.close()
