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
        self.volume_type = {'ssd':'gp2'}

        self.key_name = 'test_ssh_key'
        self.group_name = 'test_sec_group'
        self.conn = None
        self.security_group = None
        self.vpc_conn = None
        self.vpc_zone = None
        self.subnet = None
        self.elastic_ips = []
        self.instances = []

    def ec2_connect(self, region=None):
        """
        Obtain the EC2 connector by authenticating. This also creates the
        keypair and security group for the instance.
        :param region: region to connect to (optional, defaults to eu-west1)
        """
        self.conn = ec2.connect_to_region(region or self.region,
                                          aws_access_key_id=self.keyid,
                                          aws_secret_access_key=self.secret)

        self.create_key_pair(self.conn)
        self.create_security_group(self.conn)

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
        log.info('Created instance: {}'.format(instance.__dict__))

        self.instances.append(instance)

        return instance

    def vpc_connect(self, region=None):
        """
        Obtain the VPC EC2 connector by authenticating. This also creates the
        keypair and security group for the instance.
        :param region: region to connect to (optional, defaults to eu-west1)
        """
        self.vpc_conn = vpc.connect_to_region(region or self.region,
                                              aws_access_key_id=self.keyid,
                                              aws_secret_access_key=self.secret)
        self.vpc_zone = self.vpc_conn.create_vpc('10.10.0.0/16')
        self.vpc_conn.modify_vpc_attribute(self.vpc_zone.id,
                                           enable_dns_support=True)
        self.vpc_conn.modify_vpc_attribute(self.vpc_zone.id,
                                           enable_dns_hostnames=True)
        gateway = self.vpc_conn.create_internet_gateway()
        self.vpc_conn.attach_internet_gateway(gateway.id, self.vpc_zone.id)
        route_table = self.vpc_conn.create_route_table(self.vpc_zone.id)
        self.subnet = self.vpc_conn.create_subnet(self.vpc_zone.id,
                                                  '10.10.10.0/24',
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
        reservation = self.vpc_conn.run_instances(
            self.imageid, key_name=self.key_name,
            instance_type=self.instancetype,
            placement=self.zone, security_group_ids=[self.security_group.id],
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
                log.error('KeyPair: %s already exists.' % self.key_name)
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
            group = conn.create_security_group(self.group_name, 'All access',
                                               vpc_id=vpc_id)
            self.security_group = group
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
        conn = self.conn or self.vpc_conn
        # Add EBS volume DONE
        ebs_vol = conn.create_volume(size, self.zone, volume_type=volume_type,
                                     iops=iops)
        self.wait_for_state(ebs_vol, 'status', 'available')
        if not device:
            device = '/dev/sdx'
        conn.attach_volume(ebs_vol.id, instance.id, device=device)
        return ebs_vol

    def enable_sr_iov(self, instance, ssh_client):
        """
        Enable SR-IOV for a given instance.
        :param instance: EC2Instance object
        :param ssh_client: SSHClient
        :return: SSHClient (needs to reconnect after reboot)
        """
        conn = self.conn or self.vpc_conn
        sriov_status = conn.get_instance_attribute(instance.id,
                                                   'sriovNetSupport')
        log.info('Enabling SR-IOV on {}'.format(instance.id))
        if not sriov_status and ssh_client:
            util_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client.put_file(os.path.join(util_path, 'tests',
                                             'enable_sr_iov.sh'),
                                '/tmp/enable_sr_iov.sh')
            ssh_client.run('chmod +x /tmp/enable_sr_iov.sh')
            ssh_client.run("sed -i 's/\r//' /tmp/enable_sr_iov.sh")
            ssh_client.run('/tmp/enable_sr_iov.sh')
            conn.stop_instances(instance_ids=[instance.id])
            self.wait_for_state(instance, 'state', 'stopped')
            mod_sriov = conn.modify_instance_attribute(instance.id,
                                                       'sriovNetSupport',
                                                       'simple')
            log.info('Modifying SR-IOV state to simple: {}'.format(mod_sriov))
            conn.start_instances(instance_ids=[instance.id])
            self.wait_for_state(instance, 'state', 'running')

            ssh_client = self.wait_for_ping(instance)
            instance.update()
            sriov_status = conn.get_instance_attribute(instance.id,
                                                       'sriovNetSupport')
            log.info("SR-IOV status is: {}".format(sriov_status))
        return ssh_client

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
        ping_cmd = 'ping {} 1 {}'.format(ping_arg, instance.ip_address)
        try:
            timeout = 0
            while os.system(ping_cmd) != 0 or timeout >= 60:
                time.sleep(5)
                timeout += 5
            # artificial wait for ssh service up status
            time.sleep(30)
            open(host_key_file, 'w').close()
            client = sshclient_from_instance(
                instance, os.path.join(self.localpath, self.key_name + '.pem'),
                host_key_file=host_key_file, user_name=user or self.user)
        except Exception as e:
            log.error(e)
            client = None
        return client

    def teardown(self, instance=None, ebs_vol=None, device=None):
        """
        Cleanup created instances and devices.
        :param instance: EC2Instance object
        :param ebs_vol:  EBSVolume object
        :param device: EBS device mount location
        """
        conn = self.conn or self.vpc_conn
        if not instance:
            conn.terminate_instances(instance_ids=[i.id
                                                   for i in self.instances])
        else:
            conn.terminate_instances(instance_ids=[instance.id])

        for inst in self.instances:
            self.wait_for_state(inst, 'state', 'terminated')

        if ebs_vol:
            if type(ebs_vol) is not list:
                ebs_vol = [ebs_vol]
            for vol in ebs_vol:
                for inst in self.instances:
                    try:
                        if not device:
                            conn.detach_volume(vol.id, inst.id,
                                               device='/dev/sdx')
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

            subnets = self.vpc_conn.get_all_subnets(
                filters={'vpcId': self.vpc_zone.id})
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

            route_tables = self.vpc_conn.get_all_route_tables(
                filters={'vpc-id': self.vpc_zone.id})
            for route_table in route_tables:
                try:
                    self.vpc_conn.delete_route(route_table.id, '10.10.0.0/16')
                    log.info('deleted 10.10.0.0 route from table {}'.format(
                        route_table.id))
                except Exception as e:
                    log.info(e)
                try:
                    self.vpc_conn.delete_route(route_table.id, '0.0.0.0/0')
                    log.info('deleted 0.0.0.0 route from table {}'.format(
                        route_table.id))
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
                    self.vpc_conn.detach_internet_gateway(internet_gateway.id,
                                                          self.vpc_zone.id)
                    self.vpc_conn.delete_internet_gateway(internet_gateway.id)
            except Exception as e:
                log.info(e)

            self.vpc_conn.delete_vpc(vpc_id=self.vpc_zone.id)
            self.vpc_zone = None


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
    """

    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)

    if 'p2.8x' in instancetype:
        aws.vpc_connect()
        instance = aws.aws_create_vpc_instance()
    else:
        aws.ec2_connect()
        instance = aws.aws_create_instance()

    ssh_client = aws.wait_for_ping(instance)
    device = '/dev/sdx'
    ebs_vol = aws.attach_ebs_volume(instance, size=10,
                                    volume_type=aws.volume_type['ssd'],
                                    device=device)

    if ssh_client:
        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client.put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                            '/tmp/orion_linux_x86-64.gz')
        ssh_client.put_file(os.path.join(current_path, 'tests', 'run_orion.sh'),
                            '/tmp/run_orion.sh')
        ssh_client.run('chmod +x /tmp/run_orion.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_orion.sh")
        ssh_client.run('/tmp/run_orion.sh {}'.format(
                                device.replace('sd', 'xvd')))

        ssh_client.get_file('/tmp/orion.zip',
                            os.path.join(localpath,
                                         'orion' + str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vol)


def test_orion_raid(keyid, secret, imageid, instancetype, user, localpath,
                    region, zone):
    """
    Run Orion test on an EC2 Instance - using 12 x EBS gp2 SSD devices in RAID 0
    configuration for testing.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """

    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    if 'p2.8x' in instancetype:
        aws.vpc_connect()
        instance = aws.aws_create_vpc_instance()
    else:
        aws.ec2_connect()
        instance = aws.aws_create_instance()

    ssh_client = aws.wait_for_ping(instance)
    ebs_vols = []
    devices = []
    for i in xrange(12):
        device = '/dev/sd{}'.format(chr(120 - i))
        ebs_vols.append(aws.attach_ebs_volume(
            instance, size=1, volume_type=aws.volume_type['ssd'],
            device=device))
        devices.append(device.replace('sd', 'xvd'))
        time.sleep(3)

    if ssh_client:
        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client.put_file(os.path.join(current_path, 'tests', 'raid.sh'),
                            '/tmp/raid.sh')
        ssh_client.run('chmod +x /tmp/raid.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/raid.sh")
        ssh_client.run('/tmp/raid.sh 0 12 {}'.format(' '.join(devices)))
        ssh_client.put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                            '/tmp/orion_linux_x86-64.gz')
        raid = '/dev/md0'
        ssh_client.put_file(os.path.join(current_path, 'tests', 'run_orion.sh'),
                            '/tmp/run_orion.sh')
        ssh_client.run('chmod +x /tmp/run_orion.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_orion.sh")
        ssh_client.run('/tmp/run_orion.sh {}'.format(raid))

        ssh_client.get_file('/tmp/orion.zip',
                            os.path.join(localpath,
                                         'orion' + str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vols)


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
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.ec2_connect()
    instance = aws.aws_create_instance()

    ssh_client = aws.wait_for_ping(instance)
    device = '/dev/sdx'
    ebs_vol = aws.attach_ebs_volume(instance, size=240,
                                    volume_type=aws.volume_type['ssd'],
                                    device=device)

    if ssh_client:
        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client.put_file(os.path.join(current_path, 'tests',
                                         'run_sysbench.sh'),
                            '/tmp/run_sysbench.sh')
        ssh_client.run('chmod +x /tmp/run_sysbench.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_sysbench.sh")
        ssh_client.run('/tmp/run_sysbench.sh {}'.format(
            device.replace('sd', 'xvd')))
        ssh_client.get_file('/tmp/sysbench.zip',
                            os.path.join(localpath, 'sysbench' +
                                         str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vol)


def test_sysbench_raid(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone):
    """
    Run Sysbench test on an EC2 Instance with a 12 x SSD RAID0 volume.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.ec2_connect()
    instance = aws.aws_create_instance()

    ssh_client = aws.wait_for_ping(instance)
    ebs_vols = []
    devices = []
    for i in xrange(12):
        device = '/dev/sd{}'.format(chr(120 - i))
        ebs_vols.append(aws.attach_ebs_volume(
            instance, size=20, volume_type=aws.volume_type['ssd'],
            device=device))
        devices.append(device.replace('sd', 'xvd'))
        time.sleep(3)

    if ssh_client:
        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client.put_file(os.path.join(current_path, 'tests', 'raid.sh'),
                            '/tmp/raid.sh')
        ssh_client.run('chmod +x /tmp/raid.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/raid.sh")
        ssh_client.run('/tmp/raid.sh 0 12 {}'.format(' '.join(devices)))
        ssh_client.put_file(os.path.join(current_path, 'tests',
                                         'run_sysbench.sh'),
                            '/tmp/run_sysbench.sh')
        ssh_client.run('chmod +x /tmp/run_sysbench.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_sysbench.sh")
        raid = '/dev/md0'
        ssh_client.run('/tmp/run_sysbench.sh {}'.format(raid))
        ssh_client.get_file('/tmp/sysbench.zip',
                            os.path.join(localpath, 'sysbench' +
                                         str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vols)


def test_memcached(keyid, secret, imageid, instancetype, user, localpath,
                   region, zone):
    """
    Run memcached test on 2 instances in VPC to elevate AWS Enhanced Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_memcached.sh'),
                             '/tmp/run_memcached.sh')
        ssh_client1.run('chmod +x /tmp/run_memcached.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_memcached.sh")
        ssh_client1.run('/tmp/run_memcached.sh {} {}'.format(
            instance2.private_ip_address, user))
        ssh_client1.get_file('/tmp/memcached.zip',
                             os.path.join(localpath, 'memcached' +
                                          str(time.time()) + '.zip'))

    aws.teardown()


def test_redis(keyid, secret, imageid, instancetype, user, localpath, region,
               zone):
    """
    Run redis test on 2 instances in VPC to elevate AWS Enhanced Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_redis.sh'),
                             '/tmp/run_redis.sh')
        ssh_client1.run('chmod +x /tmp/run_redis.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_redis.sh")
        ssh_client1.run('/tmp/run_redis.sh {} {}'.format(
            instance2.private_ip_address, user))
        ssh_client1.get_file('/tmp/redis.zip',
                             os.path.join(localpath, 'redis' +
                                          str(time.time()) + '.zip'))

    aws.teardown()


def test_apache_bench(keyid, secret, imageid, instancetype, user, localpath,
                      region, zone):
    """
    Run apache benchmark test on 2 instances in VPC to elevate AWS Enhanced
    Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_apache_bench.sh'),
                             '/tmp/run_apache_bench.sh')
        ssh_client1.run('chmod +x /tmp/run_apache_bench.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_apache_bench.sh")
        ssh_client1.run('/tmp/run_apache_bench.sh {} {}'.format(
            instance2.private_ip_address, user))
        ssh_client1.get_file('/tmp/apache_bench.zip',
                             os.path.join(localpath, 'apache_bench' +
                                          str(time.time()) + '.zip'))

    aws.teardown()


def test_mariadb(keyid, secret, imageid, instancetype, user, localpath, region,
                 zone):
    """
    Run MariaDB test on 2 instances in VPC to elevate AWS Enhanced Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    device = '/dev/sdx'
    ebs_vol = aws.attach_ebs_volume(instance2, size=40,
                                    volume_type=aws.volume_type['ssd'],
                                    device=device)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_mariadb.sh'),
                             '/tmp/run_mariadb.sh')
        ssh_client1.run('chmod +x /tmp/run_mariadb.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_mariadb.sh")
        ssh_client1.run('/tmp/run_mariadb.sh {} {} {}'.format(
            instance2.private_ip_address, user, device.replace('sd', 'xvd')))
        ssh_client1.get_file('/tmp/mariadb.zip',
                             os.path.join(localpath, 'mariadb' +
                                          str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vol)


def test_mariadb_raid(keyid, secret, imageid, instancetype, user, localpath,
                      region, zone):
    """
    Run MariaDB test on 2 instances in VPC to elevate AWS Enhanced Networking.
    DB is installed on a 12 x SSD RAID0 volume.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    ebs_vols = []
    devices = []
    for i in xrange(12):
        device = '/dev/sd{}'.format(chr(120 - i))
        ebs_vols.append(aws.attach_ebs_volume(
            instance2, size=10, volume_type=aws.volume_type['ssd'],
            device=device))
        devices.append(device.replace('sd', 'xvd'))
        time.sleep(3)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client2.put_file(os.path.join(current_path, 'tests', 'raid.sh'),
                             '/tmp/raid.sh')
        ssh_client2.run('chmod +x /tmp/raid.sh')
        ssh_client2.run("sed -i 's/\r//' /tmp/raid.sh")
        ssh_client2.run('/tmp/raid.sh 0 12 {}'.format(' '.join(devices)))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_mariadb.sh'),
                             '/tmp/run_mariadb.sh')
        ssh_client1.run('chmod +x /tmp/run_mariadb.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_mariadb.sh")
        raid = '/dev/md0'
        ssh_client1.run('/tmp/run_mariadb.sh {} {} {}'.format(
            instance2.private_ip_address, user, raid))
        ssh_client1.get_file('/tmp/mariadb.zip',
                             os.path.join(localpath, 'mariadb' +
                                          str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vols)


def test_mongodb(keyid, secret, imageid, instancetype, user, localpath, region,
                 zone):
    """
    Run MongoDB YCBS benchmark test on 2 instances in VPC to elevate AWS
    Enhanced Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    device = '/dev/sdx'
    ebs_vol = aws.attach_ebs_volume(instance2, size=40,
                                    volume_type=aws.volume_type['ssd'],
                                    device=device)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_mongodb.sh'),
                             '/tmp/run_mongodb.sh')
        ssh_client1.run('chmod +x /tmp/run_mongodb.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_mongodb.sh")
        ssh_client1.run('/tmp/run_mongodb.sh {} {} {}'.format(
            instance2.private_ip_address, user, device.replace('sd', 'xvd')))
        ssh_client1.get_file('/tmp/mongodb.zip',
                             os.path.join(localpath, 'mongodb' +
                                          str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vol)


def test_mongodb_raid(keyid, secret, imageid, instancetype, user, localpath,
                      region, zone):
    """
    Run MongoDB YCBS benchmark test on 2 instances in VPC to elevate AWS
    Enhanced Networking. DB is installed on a 12 x SSD RAID0 volume.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instance1 = aws.aws_create_vpc_instance()
    instance2 = aws.aws_create_vpc_instance()

    ssh_client1 = aws.wait_for_ping(instance1)
    ssh_client2 = aws.wait_for_ping(instance2)

    ebs_vols = []
    devices = []
    for i in xrange(12):
        device = '/dev/sd{}'.format(chr(120 - i))
        ebs_vols.append(aws.attach_ebs_volume(
            instance2, size=10, volume_type=aws.volume_type['ssd'],
            device=device))
        devices.append(device.replace('sd', 'xvd'))
        time.sleep(3)

    if ssh_client1 and ssh_client2:
        ssh_client1 = aws.enable_sr_iov(instance1, ssh_client1)
        aws.enable_sr_iov(instance2, ssh_client2)

        # enable key auth between instances
        ssh_client1.put_file(os.path.join(localpath, aws.key_name + '.pem'),
                             '/home/{}/.ssh/id_rsa'.format(user))
        ssh_client1.run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_client2.put_file(os.path.join(current_path, 'tests', 'raid.sh'),
                             '/tmp/raid.sh')
        ssh_client2.run('chmod +x /tmp/raid.sh')
        ssh_client2.run("sed -i 's/\r//' /tmp/raid.sh")
        ssh_client2.run('/tmp/raid.sh 0 12 {}'.format(' '.join(devices)))
        ssh_client1.put_file(os.path.join(current_path, 'tests',
                                          'run_mongodb.sh'),
                             '/tmp/run_mongodb.sh')
        ssh_client1.run('chmod +x /tmp/run_mongodb.sh')
        ssh_client1.run("sed -i 's/\r//' /tmp/run_mongodb.sh")
        raid = '/dev/md0'
        ssh_client1.run('/tmp/run_mongodb.sh {} {} {}'.format(
            instance2.private_ip_address, user, raid))
        ssh_client1.get_file('/tmp/mongodb.zip',
                             os.path.join(localpath, 'mongodb' +
                                          str(time.time()) + '.zip'))

    aws.teardown(ebs_vol=ebs_vols)


def test_zookeeper(keyid, secret, imageid, instancetype, user, localpath,
                   region, zone):
    """
    Run ZooKeeper benchmark on a tree of 5 znodes and 1 client,
    in VPC to elevate AWS Enhanced Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instances = {}
    for i in range(1, 7):
        instances[i] = aws.aws_create_vpc_instance()

    ssh_clients = {}
    for i in range(1, 7):
        ssh_clients[i] = aws.wait_for_ping(instances[i])

    if all(client for client in ssh_clients.values()):
        for i in range(1, 7):
            ssh_clients[i] = aws.enable_sr_iov(instances[i], ssh_clients[i])

            # enable key auth between instances
            ssh_clients[i].put_file(os.path.join(localpath,
                                                 aws.key_name + '.pem'),
                                    '/home/{}/.ssh/id_rsa'.format(user))
            ssh_clients[i].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_clients[1].put_file(os.path.join(current_path, 'tests',
                                             'run_zookeeper.sh'),
                                '/tmp/run_zookeeper.sh')
        ssh_clients[1].run('chmod +x /tmp/run_zookeeper.sh')
        ssh_clients[1].run("sed -i 's/\r//' /tmp/run_zookeeper.sh")
        zk_servers = ' '.join([instances[i].private_ip_address
                               for i in range(2, 7)])
        ssh_clients[1].run('/tmp/run_zookeeper.sh {} {}'.format(user,
                                                                zk_servers))
        ssh_clients[1].get_file('/tmp/zookeeper.zip',
                                os.path.join(localpath, 'zookeeper' +
                                             str(time.time()) + '.zip'))

    aws.teardown()


def test_terasort(keyid, secret, imageid, instancetype, user, localpath, region,
                  zone):
    """
    Run Hadoop terasort benchmark on a tree of servers using 1 master and
    5 slaves instances in VPC to elevate AWS Enhanced Networking.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param imageid: AMI image id from EC2 repo
    :param instancetype: instance flavor constituting resources
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    aws = AWSConnector(keyid, secret, imageid, instancetype, user, localpath,
                       region, zone)
    aws.vpc_connect()
    instances = {}
    for i in range(1, 7):
        instances[i] = aws.aws_create_vpc_instance()

    ssh_clients = {}
    for i in range(1, 7):
        ssh_clients[i] = aws.wait_for_ping(instances[i])

    device = '/dev/sdx'
    ebs_vols = list()
    ebs_vols.append(aws.attach_ebs_volume(
        instances[1], size=250, volume_type=aws.volume_type['ssd'],
        device=device))
    for i in range(2, 7):
        ebs_vols.append(aws.attach_ebs_volume(
            instances[i], size=50, volume_type=aws.volume_type['ssd'],
            device=device))

    if all(client for client in ssh_clients.values()):
        for i in range(1, 7):
            ssh_clients[i] = aws.enable_sr_iov(instances[i], ssh_clients[i])

            # enable key auth between instances
            ssh_clients[i].put_file(os.path.join(localpath,
                                                 aws.key_name + '.pem'),
                                    '/home/{}/.ssh/id_rsa'.format(user))
            ssh_clients[i].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

        current_path = os.path.dirname(os.path.realpath(__file__))
        ssh_clients[1].put_file(os.path.join(current_path, 'tests',
                                             'run_terasort.sh'),
                                '/tmp/run_terasort.sh')
        ssh_clients[1].run('chmod +x /tmp/run_terasort.sh')
        ssh_clients[1].run("sed -i 's/\r//' /tmp/run_terasort.sh")
        slaves = ' '.join([instances[i].private_ip_address
                           for i in range(2, 7)])
        ssh_clients[1].run('/tmp/run_terasort.sh {} {} {}'.format(
            user, device.replace('sd', 'xvd'), slaves))
        try:
            ssh_clients[1].get_file('/tmp/terasort.zip',
                                    os.path.join(localpath, 'terasort' +
                                                 str(time.time()) + '.zip'))
        except Exception as e:
            log.info(e)

    aws.teardown(ebs_vol=ebs_vols)
