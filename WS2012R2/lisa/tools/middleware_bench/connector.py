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

from AWS import AWSConnector
from Azure import AzureConnector
from cmdshell import SSHClient

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def setup_env(provider=None, vm_count=None, test_type=None, disk_size=None, raid=None, keyid=None,
              secret=None, subscriptionid=None, tenantid=None, imageid=None, instancetype=None,
              user=None, localpath=None, region=None, zone=None):
    """
    Setup test environment, creating VMs and disk devices.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param vm_count: Number of VMs to prepare
    :param test_type: vm_disk > 1 VM with disk (Orion and Sysbench)
                      no_disk > No disk attached (Redis, Memcached, Apache_bench)
                      db_disk > Second VM with disk (MariaDB, MongoDB)
                      cluster_disk > All VMs have disks (Terasort)
    :param disk_size:
    :param raid: Bool, to specify if a RAID will be configured
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscriptionid: Azure specific subscription id
    :param tenantid: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :rtype Tuple
    :return: connector <Connector>,
             vm_ips <VM private IPs dict>,
             device <attached disk devices>,
             ssh_client <ssh clients dict>
    """
    connector = None
    device = None
    vms = {}
    vm_ips = {}
    ssh_client = {}
    try:
        if provider == constants.AWS:
            connector = AWSConnector(keyid=keyid, secret=secret, imageid=imageid,
                                     instancetype=instancetype, user=user, localpath=localpath,
                                     region=region, zone=zone)
            if instancetype == constants.AWS_P28XLARGE:
                connector.vpc_connect()
                for i in xrange(1, vm_count + 1):
                    vms[i] = connector.aws_create_vpc_instance()
            else:
                connector.ec2_connect()
                for i in xrange(1, vm_count + 1):
                    vms[i] = connector.aws_create_instance()

            for i in xrange(1, vm_count + 1):
                ssh_client[i] = connector.wait_for_ping(vms[i])
                if vm_count > 1:
                    ssh_client[i] = connector.enable_sr_iov(vms[i], ssh_client[i])
                vms[i].update()
                vm_ips[i] = vms[i].private_ip_address

            device = constants.DEVICE_AWS.replace('sd', 'xvd')
            if test_type == constants.VM_DISK:
                if raid:
                    device = []
                    for i in xrange(12):
                        dev = '/dev/sd{}'.format(chr(120 - i))
                        connector.attach_ebs_volume(vms[1], size=disk_size,
                                                    volume_type=connector.volume_type['ssd'],
                                                    device=dev)
                        device.append(dev.replace('sd', 'xvd'))
                        time.sleep(3)
                else:
                    connector.attach_ebs_volume(vms[1], size=disk_size,
                                                volume_type=connector.volume_type['ssd'],
                                                device=constants.DEVICE_AWS)
            elif test_type == constants.DB_DISK:
                if raid:
                    device = []
                    for i in xrange(12):
                        dev = '/dev/sd{}'.format(chr(120 - i))
                        connector.attach_ebs_volume(vms[2], size=disk_size,
                                                    volume_type=connector.volume_type['ssd'],
                                                    device=dev)
                        device.append(dev.replace('sd', 'xvd'))
                        time.sleep(3)
                else:
                    connector.attach_ebs_volume(vms[2], size=disk_size,
                                                volume_type=connector.volume_type['ssd'],
                                                device=constants.DEVICE_AWS)
            elif test_type == constants.CLUSTER_DISK:
                connector.attach_ebs_volume(
                        vms[1], size=disk_size + 200, volume_type=connector.volume_type['ssd'],
                        device=constants.DEVICE_AWS)
                for i in xrange(2, vm_count + 1):
                    connector.attach_ebs_volume(vms[i], size=disk_size,
                                                volume_type=connector.volume_type['ssd'],
                                                device=constants.DEVICE_AWS)
                    time.sleep(3)
        elif provider == constants.AZURE:
            connector = AzureConnector(clientid=keyid, secret=secret, subscriptionid=subscriptionid,
                                       tenantid=tenantid, imageid=imageid,
                                       instancetype=instancetype, user=user, localpath=localpath,
                                       location=region)
            connector.azure_connect()
            for i in xrange(1, vm_count + 1):
                vms[i] = connector.azure_create_vm()
            device = constants.DEVICE_AZURE
            if test_type == constants.VM_DISK:
                if raid:
                    device = []
                    for i in xrange(12):
                        log.info('Created disk: {}'.format(connector.attach_disk(vms[1], disk_size,
                                                                                 lun=i)))
                        device.append('/dev/sd{}'.format(chr(99 + i)))
                else:
                    connector.attach_disk(vms[1], disk_size)
            elif test_type == constants.DB_DISK:
                if raid:
                    device = []
                    for i in xrange(12):
                        log.info('Created disk: {}'.format(connector.attach_disk(vms[2], disk_size,
                                                                                 lun=i)))
                        device.append('/dev/sd{}'.format(chr(99 + i)))
                else:
                    connector.attach_disk(vms[2], disk_size)
            elif test_type == constants.CLUSTER_DISK:
                log.info('Created disk: {}'.format(connector.attach_disk(vms[1], disk_size + 200)))
                for i in xrange(2, vm_count + 1):
                    log.info('Created disk: {}'.format(connector.attach_disk(vms[i], disk_size)))

            for i in xrange(1, vm_count + 1):
                ssh_client[i] = SSHClient(server=vms[i].name + connector.dns_suffix,
                                          host_key_file=connector.host_key_file,
                                          user=connector.user,
                                          ssh_key_file=os.path.join(connector.localpath,
                                                                    connector.key_name + '.pem'))
                cmd = ssh_client[i].run(
                        'ifconfig eth0 | grep "inet\ addr" | cut -d: -f2 | cut -d" " -f1')
                vm_ips[i] = cmd[1].strip()
        elif provider == constants.GCE:
            pass
    except Exception as e:
        log.error(e)
        if connector:
            connector.teardown()
        raise

    return connector, vm_ips, device, ssh_client


def test_orion(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
               localpath, region, zone):
    """
    Run Orion test.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK, disk_size=10,
                                                      raid=False, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                                   '/tmp/orion_linux_x86-64.gz')
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_orion.sh'),
                                   '/tmp/run_orion.sh')
            ssh_client[1].run('chmod +x /tmp/run_orion.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_orion.sh")
            ssh_client[1].run('/tmp/run_orion.sh {}'.format(device))

            ssh_client[1].get_file('/tmp/orion.zip',
                                   os.path.join(localpath, 'orion' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_orion_raid(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                    localpath, region, zone):
    """
    Run Orion test using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK, disk_size=1,
                                                      raid=True, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
            ssh_client[1].run('chmod +x /tmp/raid.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/raid.sh")
            ssh_client[1].run('/tmp/raid.sh 0 12 {}'.format(' '.join(device)))
            ssh_client[1].put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                                   '/tmp/orion_linux_x86-64.gz')
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_orion.sh'),
                                   '/tmp/run_orion.sh')
            ssh_client[1].run('chmod +x /tmp/run_orion.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_orion.sh")
            ssh_client[1].run('/tmp/run_orion.sh {}'.format(constants.RAID_DEV))

            ssh_client[1].get_file('/tmp/orion.zip',
                                   os.path.join(localpath, 'orion' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_sysbench(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                  localpath, region, zone):
    """
    Run Sysbench test.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK, disk_size=240,
                                                      raid=False, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_sysbench.sh'),
                                   '/tmp/run_sysbench.sh')
            ssh_client[1].run('chmod +x /tmp/run_sysbench.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_sysbench.sh")
            ssh_client[1].run('/tmp/run_sysbench.sh {}'.format(device))
            ssh_client[1].get_file('/tmp/sysbench.zip',
                                   os.path.join(localpath, 'sysbench' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_sysbench_raid(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                       localpath, region, zone):
    """
    Run Sysbench test using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK, disk_size=20,
                                                      raid=True, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
            ssh_client[1].run('chmod +x /tmp/raid.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/raid.sh")
            ssh_client[1].run('/tmp/raid.sh 0 12 {}'.format(' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_sysbench.sh'),
                                   '/tmp/run_sysbench.sh')
            ssh_client[1].run('chmod +x /tmp/run_sysbench.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_sysbench.sh")
            ssh_client[1].run('/tmp/run_sysbench.sh {}'.format(constants.RAID_DEV))
            ssh_client[1].get_file('/tmp/sysbench.zip',
                                   os.path.join(localpath, 'sysbench' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_memcached(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                   localpath, region, zone):
    """
    Run memcached test on 2 instances.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_memcached.sh'),
                                   '/tmp/run_memcached.sh')
            ssh_client[1].run('chmod +x /tmp/run_memcached.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_memcached.sh")
            ssh_client[1].run('/tmp/run_memcached.sh {} {}'.format(vm_ips[2], user))
            ssh_client[1].get_file('/tmp/memcached.zip',
                                   os.path.join(localpath, 'memcached' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_redis(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
               localpath, region, zone):
    """
    Run redis test on 2 instances.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_redis.sh'),
                                   '/tmp/run_redis.sh')
            ssh_client[1].run('chmod +x /tmp/run_redis.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_redis.sh")
            ssh_client[1].run('/tmp/run_redis.sh {} {}'.format(vm_ips[2], user))
            ssh_client[1].get_file('/tmp/redis.zip',
                                   os.path.join(localpath, 'redis' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_apache_bench(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                      localpath, region, zone):
    """
    Run Apache Benchmark test on 2 instances.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_apache_bench.sh'),
                                   '/tmp/run_apache_bench.sh')
            ssh_client[1].run('chmod +x /tmp/run_apache_bench.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_apache_bench.sh")
            ssh_client[1].run('/tmp/run_apache_bench.sh {} {}'.format(vm_ips[2], user))
            ssh_client[1].get_file(
                    '/tmp/apache_bench.zip',
                    os.path.join(localpath, 'apache_bench' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_mariadb(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                 localpath, region, zone):
    """
    Run MariaDB test on 2 instances.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK, disk_size=40,
                                                      raid=False, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_mariadb.sh'),
                                   '/tmp/run_mariadb.sh')
            ssh_client[1].run('chmod +x /tmp/run_mariadb.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_mariadb.sh")
            ssh_client[1].run('/tmp/run_mariadb.sh {} {} {}'.format(vm_ips[2], user, device))
            ssh_client[1].get_file('/tmp/mariadb.zip',
                                   os.path.join(localpath, 'mariadb' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_mariadb_raid(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                      localpath, region, zone):
    """
    Run MariaDB test on 2 instances using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK, disk_size=10,
                                                      raid=True, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[2].put_file(os.path.join(current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
            ssh_client[2].run('chmod +x /tmp/raid.sh')
            ssh_client[2].run("sed -i 's/\r//' /tmp/raid.sh")
            ssh_client[2].run('/tmp/raid.sh 0 12 {}'.format(' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_mariadb.sh'),
                                   '/tmp/run_mariadb.sh')
            ssh_client[1].run('chmod +x /tmp/run_mariadb.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_mariadb.sh")
            ssh_client[1].run('/tmp/run_mariadb.sh {} {} {}'.format(vm_ips[2], user,
                                                                    constants.RAID_DEV))
            ssh_client[1].get_file('/tmp/mariadb.zip',
                                   os.path.join(localpath, 'mariadb' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_mongodb(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                 localpath, region, zone):
    """
    Run MongoDB YCBS benchmark test on 2 instances.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK, disk_size=40,
                                                      raid=False, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_mongodb.sh'),
                                   '/tmp/run_mongodb.sh')
            ssh_client[1].run('chmod +x /tmp/run_mongodb.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_mongodb.sh")
            ssh_client[1].run('/tmp/run_mongodb.sh {} {} {}'.format(vm_ips[2], user, device))
            ssh_client[1].get_file('/tmp/mongodb.zip',
                                   os.path.join(localpath, 'mongodb' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_mongodb_raid(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                      localpath, region, zone):
    """
    Run MongoDB YCBS benchmark test on 2 instances using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK, disk_size=10,
                                                      raid=True, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)
    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[2].put_file(os.path.join(current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
            ssh_client[2].run('chmod +x /tmp/raid.sh')
            ssh_client[2].run("sed -i 's/\r//' /tmp/raid.sh")
            ssh_client[2].run('/tmp/raid.sh 0 12 {}'.format(' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_mongodb.sh'),
                                   '/tmp/run_mongodb.sh')
            ssh_client[1].run('chmod +x /tmp/run_mongodb.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_mongodb.sh")
            ssh_client[1].run('/tmp/run_mongodb.sh {} {} {}'.format(vm_ips[2], user,
                                                                    constants.RAID_DEV))
            ssh_client[1].get_file('/tmp/mongodb.zip',
                                   os.path.join(localpath, 'mongodb' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_zookeeper(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                   localpath, region, zone):
    """
    Run ZooKeeper benchmark on a tree of 5 servers and 1 generating client.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=6,
                                                      test_type=None, disk_size=None,
                                                      raid=False, keyid=keyid, secret=secret,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath, region=region,
                                                      zone=zone)

    try:
        if all(client for client in ssh_client.values()):
            for i in range(1, 7):
                # enable key auth between instances
                ssh_client[i].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                       '/home/{}/.ssh/id_rsa'.format(user))
                ssh_client[i].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))
    
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_zookeeper.sh'),
                                   '/tmp/run_zookeeper.sh')
            ssh_client[1].run('chmod +x /tmp/run_zookeeper.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_zookeeper.sh")
            zk_servers = ' '.join([vm_ips[i] for i in range(2, 7)])
            ssh_client[1].run('/tmp/run_zookeeper.sh {} {}'.format(user, zk_servers))
            ssh_client[1].get_file('/tmp/zookeeper.zip',
                                   os.path.join(localpath, 'zookeeper' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()


def test_terasort(provider, keyid, secret, imageid, subscription, tenant, instancetype, user,
                  localpath, region, zone):
    """
    Run Hadoop terasort benchmark on a tree of servers using 1 master and
    5 slaves instances in VPC to elevate AWS Enhanced Networking.
    :param provider Service provider to be used e.g. azure, middleware_bench, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=6,
                                                      test_type=constants.CLUSTER_DISK,
                                                      disk_size=50, raid=False, keyid=keyid,
                                                      secret=secret, subscriptionid=subscription,
                                                      tenantid=tenant, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region, zone=zone)
    try:
        if all(client for client in ssh_client.values()):
            for i in range(1, 7):
                # enable key auth between instances
                ssh_client[i].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                       '/home/{}/.ssh/id_rsa'.format(user))
                ssh_client[i].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_terasort.sh'),
                                   '/tmp/run_terasort.sh')
            ssh_client[1].run('chmod +x /tmp/run_terasort.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_terasort.sh")
            slaves = ' '.join([vm_ips[i] for i in range(2, 7)])
            ssh_client[1].run('/tmp/run_terasort.sh {} {} {}'.format(user, device, slaves))
            ssh_client[1].get_file('/tmp/terasort.zip',
                                   os.path.join(localpath, 'terasort' + str(time.time()) + '.zip'))
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
