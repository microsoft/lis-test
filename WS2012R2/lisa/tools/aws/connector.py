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

import boto.ec2
from boto.manage.cmdshell import sshclient_from_instance

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class AWSConnector:
    """
    AWS EC2 connector that uses boto plugin.
    """
    def __init__(self, keyid=None, secret=None, imageid=None, instancetype=None,
                 user=None, localpath=None, region=None, zone=None):
        """
        Init AWS connector to create and configure aws ec2 instances.
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

        self.key_name = 'test_ssh_key'
        self.group_name = 'test_sec_group'
        self.conn = self.ec2_connect()

    @staticmethod
    def wait_for_state(obj, attr, state):
        """
        Check when an aws object attribute state is achieved.
        :param obj: the aws object to verify attribute status
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
            log.error("Spawned instance was not allocated a public IP. "
                      "Please try again.")
            raise
        ping_cmd = 'ping {} 1 {}'.format(ping_arg, instance.public_dns_name)
        try:
            timeout = 0
            while os.system(ping_cmd) != 0 or timeout >= 60:
                time.sleep(5)
                timeout += 5
            # artificial wait for ssh service up status
            time.sleep(30)
            open(host_key_file, 'w').close()
            client = sshclient_from_instance(instance,
                                             os.path.join(self.localpath,
                                                      self.key_name + '.pem'),
                                             host_key_file=host_key_file,
                                             user_name=user or self.user)
        except Exception as e:
            log.error(e)
            client = None
        return client

    def ec2_connect(self, region=None):
        """
        Obtain the EC2 connector by authenticating. This also creates the
        keypair and security group for the instance.
        :param region: region to connect to (optional, defaults to eu-west1)
        :return: EC2Connection
        """
        conn = boto.ec2.connect_to_region(region or self.region,
                                          aws_access_key_id=self.keyid,
                                          aws_secret_access_key=self.secret)

        try:
            key_pair = conn.create_key_pair(self.key_name)
            key_pair.save(self.localpath)
        except conn.ResponseError as e:
            if e.code == 'InvalidKeyPair.Duplicate':
                log.error('KeyPair: %s already exists.' % self.key_name)
            else:
                raise
        cidr = '0.0.0.0/0'
        try:
            group = conn.create_security_group(self.group_name, 'All access')
            group.authorize(ip_protocol='tcp', from_port=0, to_port=65535,
                            cidr_ip=cidr)
            group.authorize(ip_protocol='tcp', from_port=22, to_port=22,
                            cidr_ip=cidr)
            group.authorize(ip_protocol='udp', from_port=0, to_port=65535,
                            cidr_ip=cidr)
            group.authorize(ip_protocol='icmp', from_port=-1, to_port=-1,
                            cidr_ip=cidr)
        except conn.ResponseError as e:
            if e.code == 'InvalidGroup.Duplicate':
                log.warning('Security Group: {} already exists.'.format(
                    self.group_name))
            elif e.code == 'InvalidPermission.Duplicate':
                log.warning('Security Group: {} already authorized'.format(
                    self.group_name))
            else:
                raise

        return conn

    def attach_ebs_volume(self, instance, size=10, volume_type=None, iops=None,
                          device=None):
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
        # Add EBS volume DONE
        ebs_vol = self.conn.create_volume(size, self.zone,
                                          volume_type=volume_type, iops=iops)
        self.wait_for_state(ebs_vol, 'status', 'available')
        if not device:
            device = '/dev/sdx'
        self.conn.attach_volume(ebs_vol.id, instance.id, device=device)
        return ebs_vol

    def aws_create_instance(self, user_data=None):
        """
        Create an EC2 instance.
        :param user_data: routines to be executed upon spawning the instance
        :return: EC2Instance object
        """
        reservation = self.conn.run_instances(self.imageid,
                                              key_name=self.key_name,
                                              instance_type=self.instancetype,
                                              placement=self.zone,
                                              security_groups=[self.group_name],
                                              user_data=user_data)
        instance = reservation.instances[0]
        time.sleep(5)
        self.wait_for_state(instance, 'state', 'running')

        # artificial wait for public ip
        time.sleep(5)
        instance.update()
        log.info(instance.__dict__)

        return instance

    def enable_sr_iov(self, instance, ssh_client):
        """
        Enable SR-IOV for given instance
        :param instance: EC2Instance object
        :param ssh_client: SSHClient
        :return: SR-IOv status
        """
        sriov_status = self.conn.get_instance_attribute(instance.id,
                                                        'sriovNetSupport')
        if not sriov_status and ssh_client:
            # status, stdout, stderr = ssh_client.run(check_systemd)
            systemd_ver = stdout.split('-')[1]
            # if int(systemd_ver) > 197:
            #     ssh_client.run(disable_predictable_cmd)
            self.conn.stop_instances(instance_ids=[instance.id])
            self.wait_for_state(instance, 'state', 'stopped')
            self.conn.modify_instance_attribute(instance.id, 'sriovNetSupport',
                                                'simple')
            self.conn.start_instances(instance_ids=[instance.id])
            self.wait_for_state(instance, 'state', 'running')

            self.wait_for_ping(instance)
            sriov_status = self.conn.get_instance_attribute(instance.id,
                                                            'sriovNetSupport')
        return sriov_status

    def teardown(self, instance, ebs_vol=None, device=None):
        """
        Cleanup created instances and devices.
        :param instance: EC2Instance object
        :param ebs_vol:  EBSVolume object
        :param device: EBS device mount location
        :return:
        """
        # teardown
        if ebs_vol:
            if not device:
                device = '/dev/sdx'
            print(ebs_vol.__dict__)
            self.conn.detach_volume(ebs_vol.id, instance.id, device=device,
                                    force=True)
            print(ebs_vol.__dict__)
            self.wait_for_state(ebs_vol, 'status', 'available')
            print(ebs_vol.__dict__)
            # artificial wait
            time.sleep(30)
            self.conn.delete_volume(ebs_vol.id)
        self.conn.terminate_instances(instance_ids=[instance.id])


def test_orion(keyid, secret, imageid, instancetype, user, localpath, region,
               zone):
    """
    Run Orion test on an EC2 Instance - using an EBS gp2 SSD device for testing.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :return:
    """
    volume_type = 'gp2'

    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.ec2_connect()
    instance = aws.aws_create_instance()

    ssh_client = aws.wait_for_ping(instance)
    ebs_vol = aws.attach_ebs_volume(instance, size=10, volume_type=volume_type)

    if ssh_client:
        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client.put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                            '/tmp/orion_linux_x86-64.gz')
        ssh_client.put_file(os.path.join(current_path, 'run_orion.sh'),
                            '/tmp/run_orion.sh')
        ssh_client.run('chmod +x /tmp/run_orion.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_orion.sh")
        ssh_client.run('/tmp/run_orion.sh')

        ssh_client.get_file('/tmp/orion.zip',
                            os.path.join(localpath,
                                         'orion' + str(time.time()) + '.zip'))

    aws.teardown(instance, ebs_vol)


def test_sysbench(keyid, secret, imageid, instancetype, user, localpath,
                  region, zone):
    """
    Run Sysbench test on an EC2 Instance.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :return:
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.ec2_connect()
    instance = aws.aws_create_instance()

    ssh_client = aws.wait_for_ping(instance)

    if ssh_client:
        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client.put_file(os.path.join(current_path, 'run_sysbench.sh'),
                            '/tmp/run_sysbench.sh')
        ssh_client.run('chmod +x /tmp/run_sysbench.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_sysbench.sh")
        ssh_client.run('/tmp/run_sysbench.sh')
        ssh_client.get_file('/tmp/sysbench.zip', os.path.join(localpath,
                                     'sysbench' + str(time.time()) + '.zip'))

    aws.teardown(instance)


def test_test(keyid, secret, imageid, instancetype, user, localpath, region,
              zone):
    import inspect
    frame = inspect.currentframe()
    args, _, _, values = inspect.getargvalues(frame)
    print(args, values)
    current_path = os.path.dirname(os.path.realpath(__file__))
    print(current_path)
    print(os.path.join(current_path, "run_orion.sh"))
    # import paramiko
    # ssh = paramiko.SSHClient()
    # ssh.set_missing_host_key_policy(
    #     paramiko.AutoAddPolicy())
    # ssh.connect('192.168.126.145', username='test', password='opsware')
    # _, stdout, stderr = ssh.exec_command('/tmp/test.sh', get_pty=False)
    # read_err = stderr.read(1024)
    # while read_err:
    #     stderr += read_err
    #     read_err = stderr.read(1024)
    # print(stderr)
    # pprint(stdout.readlines())
    # pprint(stderr.readlines())
