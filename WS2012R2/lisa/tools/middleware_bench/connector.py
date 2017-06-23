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
import utils

from AWS import AWSConnector
from Azure import AzureConnector
from GCE import GCEConnector
from cmdshell import SSHClient

from db_utils import upload_results
from results_parser import OrionLogsReader, SysbenchLogsReader, MemcachedLogsReader,\
    RedisLogsReader, ApacheLogsReader, MariadbLogsReader, MongodbLogsReader, ZookeeperLogsReader,\
    TerasortLogsReader, TCPLogsReader, LatencyLogsReader, StorageLogsReader

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def setup_env(provider=None, vm_count=None, test_type=None, disk_size=None, raid=None, keyid=None,
              secret=None, token=None, subscriptionid=None, tenantid=None, projectid=None,
              imageid=None, instancetype=None, user=None, localpath=None, region=None, zone=None,
              sriov=False, kernel=None):
    """
    Setup test environment, creating VMs and disk devices.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param vm_count: Number of VMs to prepare
    :param test_type: vm_disk > 1 VM with disk (Orion and Sysbench)
                      no_disk > No disk attached (Redis, Memcached, Apache_bench)
                      db_disk > Second VM with disk (MariaDB, MongoDB)
                      cluster_disk > All VMs have disks (Terasort)
    :param disk_size:
    :param raid: Bool or Int (the number of disks), to specify if a RAID will be configured
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscriptionid: Azure specific subscription id
    :param tenantid: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS' or
                    GCE image family, e.g. 'ubuntu-1604-lts'
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2' or
                        GCE instance size e.g. 'n1-highmem-16'
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: region to connect to
    :param zone: zone where other resources should be available
    :param sriov: bool for configuring SR-IOV or not
    :param kernel: kernel deb name to install provided in localpath
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
            connector.vpc_connect()
            for i in xrange(1, vm_count + 1):
                vms[i] = connector.aws_create_vpc_instance()

            for i in xrange(1, vm_count + 1):
                ssh_client[i] = connector.wait_for_ping(vms[i])
                if sriov == constants.ENABLED:
                    ssh_client[i] = connector.enable_sr_iov(vms[i], ssh_client[i])
                vms[i].update()
                vm_ips[i] = vms[i].private_ip_address

            device = constants.DEVICE_AWS.replace('sd', 'xvd')
            if test_type == constants.VM_DISK:
                if raid and type(raid) is int:
                    device = []
                    for i in xrange(raid):
                        dev = '/dev/sd{}'.format(chr(120 - i))
                        connector.attach_ebs_volume(vms[1], size=disk_size, iops=50 * disk_size,
                                                    volume_type=connector.volume_type['ssd_io1'],
                                                    device=dev)
                        device.append(dev.replace('sd', 'xvd'))
                        time.sleep(3)
                else:
                    connector.attach_ebs_volume(vms[1], size=disk_size, iops=50 * disk_size,
                                                volume_type=connector.volume_type['ssd_io1'],
                                                device=constants.DEVICE_AWS)
            elif test_type == constants.DB_DISK:
                if raid and type(raid) is int:
                    device = []
                    for i in xrange(raid):
                        dev = '/dev/sd{}'.format(chr(120 - i))
                        connector.attach_ebs_volume(vms[2], size=disk_size, iops=50 * disk_size,
                                                    volume_type=connector.volume_type['ssd_io1'],
                                                    device=dev)
                        device.append(dev.replace('sd', 'xvd'))
                        time.sleep(3)
                else:
                    connector.attach_ebs_volume(vms[2], size=disk_size, iops=50 * disk_size,
                                                volume_type=connector.volume_type['ssd_io1'],
                                                device=constants.DEVICE_AWS)
            elif test_type == constants.CLUSTER_DISK:
                connector.attach_ebs_volume(vms[1], size=disk_size + 200,
                                            iops=50 * (disk_size + 200),
                                            volume_type=connector.volume_type['ssd_io1'],
                                            device=constants.DEVICE_AWS)
                for i in xrange(2, vm_count + 1):
                    connector.attach_ebs_volume(vms[i], size=disk_size, iops=50 * disk_size,
                                                volume_type=connector.volume_type['ssd_io1'],
                                                device=constants.DEVICE_AWS)
                    time.sleep(3)
        elif provider == constants.AZURE:
            connector = AzureConnector(clientid=keyid, secret=secret,
                                       subscriptionid=subscriptionid, tenantid=tenantid,
                                       imageid=imageid, instancetype=instancetype, user=user,
                                       localpath=localpath, location=region, sriov=sriov)
            connector.azure_connect()
            for i in xrange(1, vm_count + 1):
                vms[i] = connector.azure_create_vm()
            device = constants.DEVICE_AZURE
            if test_type == constants.VM_DISK:
                if raid and type(raid) is int:
                    device = []
                    for i in xrange(raid):
                        log.info('Created disk: {}'.format(connector.attach_disk(vms[1], disk_size,
                                                                                 lun=i)))
                        device.append('/dev/sd{}'.format(chr(99 + i)))
                else:
                    connector.attach_disk(vms[1], disk_size)
            elif test_type == constants.DB_DISK:
                if raid and type(raid) is int:
                    device = []
                    for i in xrange(raid):
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
            connector = GCEConnector(clientid=keyid, secret=secret, token=token,
                                     projectid=projectid, imageid=imageid,
                                     instancetype=instancetype, user=user, localpath=localpath,
                                     zone=zone)
            connector.gce_connect()
            for i in xrange(1, vm_count + 1):
                vms[i] = connector.gce_create_vm()
            for i in xrange(1, vm_count + 1):
                ssh_client[i] = connector.wait_for_ping(vms[i])
                vm_ips[i] = vms[i]['networkInterfaces'][0]['networkIP']
            if test_type == constants.VM_DISK:
                if raid and type(raid) is int:
                    device = []
                    for i in xrange(raid):
                        disk_name = connector.attach_disk(vms[1]['name'], disk_size)
                        log.info('Created disk: {}'.format(disk_name))
                        device.append('/dev/sd{}'.format(chr(98 + i)))
                        # device.append(constants.DEVICE_GCE + disk_name)
                else:
                    disk_name = connector.attach_disk(vms[1]['name'], disk_size)
                    log.info('Created disk: {}'.format(disk_name))
                    # Note: using disk device order prediction,
                    # as the GCE API is not consistent in the disk naming/detection scheme
                    # device = constants.DEVICE_GCE + disk_name
                    device = constants.TEMP_DEVICE_GCE
            elif test_type == constants.DB_DISK:
                if raid and type(raid) is int:
                    device = []
                    for i in xrange(raid):
                        disk_name = connector.attach_disk(vms[2]['name'], disk_size)
                        log.info('Created disk: {}'.format(disk_name))
                        device.append('/dev/sd{}'.format(chr(98 + i)))
                        # device.append(constants.DEVICE_GCE + disk_name)
                else:
                    disk_name = connector.attach_disk(vms[2]['name'], disk_size)
                    log.info('Created disk: {}'.format(disk_name))
                    device = constants.TEMP_DEVICE_GCE
                    # device = constants.DEVICE_GCE + disk_name
            elif test_type == constants.CLUSTER_DISK:
                disk_name = connector.attach_disk(vms[1]['name'], disk_size + 200)
                log.info('Created disk: {}'.format(disk_name))
                for i in xrange(2, vm_count + 1):
                    disk_name = connector.attach_disk(vms[i]['name'], disk_size)
                    log.info('Created disk: {}'.format(disk_name))
                device = constants.TEMP_DEVICE_GCE

        # setup perf tuning parameters
        current_path = os.path.dirname(os.path.realpath(__file__))
        for i in range(1, vm_count + 1):
            log.info('Running perf tuning on {}'.format(vm_ips[i]))
            ssh_client[i].put_file(os.path.join(current_path, 'tests', 'perf_tuning.sh'),
                                   '/tmp/perf_tuning.sh')
            ssh_client[i].run('chmod +x /tmp/perf_tuning.sh')
            ssh_client[i].run("sed -i 's/\r//' /tmp/perf_tuning.sh")
            params = [provider]
            if '.deb' in kernel:
                log.info('Uploading kernel {} on {}'.format(kernel, vm_ips[i]))
                ssh_client[i].put_file(os.path.join(localpath, kernel),
                                       '/tmp/{}'.format(kernel))
                params.append('/tmp/{}'.format(kernel))
            ssh_client[i].run('/tmp/perf_tuning.sh {}'.format(' '.join(params)))
            if '.deb' in kernel:
                vms[i] = connector.restart_vm(vms[i].name)
                # TODO add custom kernel support for all providers - only azure support
                ssh_client[i] = SSHClient(server=vms[i].name + connector.dns_suffix,
                                          host_key_file=connector.host_key_file,
                                          user=connector.user,
                                          ssh_key_file=os.path.join(connector.localpath,
                                                                    connector.key_name + '.pem'))
                cmd = ssh_client[i].run(
                        'ifconfig eth0 | grep "inet\ addr" | cut -d: -f2 | cut -d" " -f1')
                vm_ips[i] = cmd[1].strip()

    except Exception as e:
        log.error(e)
        if connector:
            connector.teardown()
        raise

    return connector, vm_ips, device, ssh_client


def test_orion(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
               instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Orion test.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    disk_size = 0
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK,
                                                      disk_size=disk_size, raid=False,
                                                      keyid=keyid, secret=secret,
                                                      token=token, subscriptionid=subscription,
                                                      tenantid=tenant, projectid=projectid,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath,
                                                      region=region, zone=zone, sriov=sriov,
                                                      kernel=kernel)
    results_path = None
    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                                   '/tmp/orion_linux_x86-64.gz')
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_orion.sh'),
                                   '/tmp/run_orion.sh')
            ssh_client[1].run('chmod +x /tmp/run_orion.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_orion.sh")
            cmd = '/tmp/run_orion.sh {}'.format(device)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'orion{}_{}.zip'.format(str(time.time()),
                                                                           instancetype))
            ssh_client[1].get_file('/tmp/orion.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Orion'.format(provider),
                       results_path=results_path, parser=OrionLogsReader,
                       test_case_name='{}_Orion_perf_tuned'.format(provider),
                       host_type=utils.host_type(provider), instance_size=instancetype,
                       disk_setup='1 x SSD {}GB'.format(disk_size))


def test_orion_raid(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                    instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Orion test using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    raid = 0
    disk_size = 0
    if provider == constants.AWS:
        raid = 10
        disk_size = 100
    elif provider == constants.AZURE:
        raid = 10
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK,
                                                      disk_size=disk_size, raid=raid, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                                   '/tmp/orion_linux_x86-64.gz')
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_orion.sh'),
                                   '/tmp/run_orion.sh')
            ssh_client[1].run('chmod +x /tmp/run_orion.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_orion.sh")
            cmd = '/tmp/run_orion.sh {}'.format(' '.join(device))
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'orion{}_{}.zip'.format(str(time.time()),
                                                                           instancetype))
            ssh_client[1].get_file('/tmp/orion.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Orion'.format(provider),
                       results_path=results_path, parser=OrionLogsReader,
                       test_case_name='{}_Orion_perf_tuned'.format(provider),
                       host_type=utils.host_type(provider), instance_size=instancetype,
                       disk_setup='{} x SSD {}GB'.format(raid, disk_size))


def test_sysbench(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                  instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Sysbench test.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    disk_size = 0
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    results_path = None
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK,
                                                      disk_size=disk_size, raid=False,
                                                      keyid=keyid, secret=secret,
                                                      token=token, subscriptionid=subscription,
                                                      tenantid=tenant, projectid=projectid,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath,
                                                      region=region, zone=zone, sriov=sriov,
                                                      kernel=kernel)
    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_sysbench.sh'),
                                   '/tmp/run_sysbench.sh')
            ssh_client[1].run('chmod +x /tmp/run_sysbench.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_sysbench.sh")
            cmd = '/tmp/run_sysbench.sh {}'.format(device)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'sysbench{}_{}.zip'.format(str(time.time()),
                                                                              instancetype))
            ssh_client[1].get_file('/tmp/sysbench.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Sysbench'.format(provider),
                       results_path=results_path, parser=SysbenchLogsReader,
                       test_case_name='{}_sysbench_fileio_perf_tuned'.format(provider),
                       host_type=utils.host_type(provider), instance_size=instancetype,
                       disk_setup='1 x SSD {}GB'.format(disk_size))


def test_sysbench_raid(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                       instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Sysbench test using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    raid = 0
    disk_size = 0
    if provider == constants.AWS:
        raid = 10
        disk_size = 100
    elif provider == constants.AZURE:
        raid = 10
        disk_size = 513
    results_path = None
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK,
                                                      disk_size=disk_size, raid=raid, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
            ssh_client[1].run('chmod +x /tmp/raid.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/raid.sh")
            ssh_client[1].run('/tmp/raid.sh 0 {} {}'.format(raid, ' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_sysbench.sh'),
                                   '/tmp/run_sysbench.sh')
            ssh_client[1].run('chmod +x /tmp/run_sysbench.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_sysbench.sh")
            cmd = '/tmp/run_sysbench.sh {}'.format(constants.RAID_DEV)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'sysbench{}_{}.zip'.format(str(time.time()),
                                                                              instancetype))
            ssh_client[1].get_file('/tmp/sysbench.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Sysbench'.format(provider),
                       results_path=results_path, parser=SysbenchLogsReader,
                       test_case_name='{}_sysbench_fileio_perf_tuned'.format(provider),
                       host_type=utils.host_type(provider), instance_size=instancetype,
                       disk_setup='{} x SSD {}GB RAID0'.format(raid, disk_size))


def test_memcached(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                   instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run memcached test on 2 instances.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_memcached.sh {} {}'.format(vm_ips[2], user)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            log.info(ssh_client[1].run('uname -r'))
            results_path = os.path.join(localpath, 'memcached{}_{}.zip'.format(str(time.time()),
                                                                               instancetype))
            ssh_client[1].get_file('/tmp/memcached.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Memcached'.format(provider),
                       results_path=results_path, parser=MemcachedLogsReader,
                       test_case_name='{}_memcached_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype)


def test_redis(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
               instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run redis test on 2 instances.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_redis.sh {} {}'.format(vm_ips[2], user)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'redis{}_{}.zip'.format(str(time.time()),
                                                                           instancetype))
            ssh_client[1].get_file('/tmp/redis.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Redis'.format(provider),
                       results_path=results_path, parser=RedisLogsReader,
                       test_case_name='{}_redis_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype)


def test_apache_bench(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                      instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Apache Benchmark on Apache web server.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    vm_count = 2
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=vm_count,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_apache_bench.sh {} {}'.format(vm_ips[2], user)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'apache_bench{}_{}.zip'.format(str(time.time()),
                                                                                  instancetype))
            ssh_client[1].get_file('/tmp/apache_bench.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Apache'.format(provider),
                       results_path=results_path, parser=ApacheLogsReader,
                       test_case_name='{}_Apache_bench_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype)


def test_nginx_bench(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                     instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Apache Benchmark on Nginx web server.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    vm_count = 2
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=vm_count,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_nginx_bench.sh'),
                                   '/tmp/run_nginx_bench.sh')
            ssh_client[1].run('chmod +x /tmp/run_nginx_bench.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_nginx_bench.sh")
            cmd = '/tmp/run_nginx_bench.sh {} {}'.format(vm_ips[2], user)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'nginx_bench{}_{}.zip'.format(str(time.time()),
                                                                                 instancetype))
            ssh_client[1].get_file('/tmp/nginx_bench.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Nginx'.format(provider),
                       results_path=results_path, parser=ApacheLogsReader,
                       test_case_name='{}_Apache_bench_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype)


def test_mariadb(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                 instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run MariaDB test on 2 instances.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    disk_size = 0
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK,
                                                      disk_size=disk_size, raid=False, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_mariadb.sh {} {} {}'.format(vm_ips[2], user, device)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'mariadb{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/mariadb.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_MariaDB'.format(provider),
                       results_path=results_path, parser=MariadbLogsReader,
                       test_case_name='{}_MariaDB_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype, disk_setup='1 x SSD {}GB'.format(disk_size))


def test_mariadb_raid(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                      instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run MariaDB test on 2 instances using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    raid = 0
    disk_size = 0
    if provider == constants.AWS:
        raid = 10
        disk_size = 100
    elif provider == constants.AZURE:
        raid = 10
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK,
                                                      disk_size=disk_size, raid=raid, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            ssh_client[2].run('/tmp/raid.sh 0 {} {}'.format(raid, ' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_mariadb.sh'),
                                   '/tmp/run_mariadb.sh')
            ssh_client[1].run('chmod +x /tmp/run_mariadb.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_mariadb.sh")
            cmd = '/tmp/run_mariadb.sh {} {} {}'.format(vm_ips[2], user, constants.RAID_DEV)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'mariadb{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/mariadb.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_MariaDB'.format(provider),
                       results_path=results_path, parser=MariadbLogsReader,
                       test_case_name='{}_MariaDB_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype,
                       disk_setup='{} x SSD {}GB RAID0'.format(raid, disk_size))


def test_mongodb(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                 instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run MongoDB YCBS benchmark test on 2 instances.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    disk_size = 0
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK,
                                                      disk_size=disk_size, raid=False, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_mongodb.sh {} {} {}'.format(vm_ips[2], user, device)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'mongodb{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/mongodb.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_MongoDB'.format(provider),
                       results_path=results_path, parser=MongodbLogsReader,
                       test_case_name='{}_MongoDB_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype, disk_setup='1 x SSD {}GB'.format(disk_size))


def test_mongodb_raid(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                      instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run MongoDB YCBS benchmark test on 2 instances using 12 x SSD devices in RAID 0.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    raid = 0
    disk_size = 0
    if provider == constants.AWS:
        raid = 10
        disk_size = 100
    elif provider == constants.AZURE:
        raid = 10
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=constants.DB_DISK,
                                                      disk_size=disk_size, raid=raid, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            ssh_client[2].run('/tmp/raid.sh 0 {} {}'.format(raid, ' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_mongodb.sh'),
                                   '/tmp/run_mongodb.sh')
            ssh_client[1].run('chmod +x /tmp/run_mongodb.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_mongodb.sh")
            cmd = '/tmp/run_mongodb.sh {} {} {}'.format(vm_ips[2], user, constants.RAID_DEV)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'mongodb{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/mongodb.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_MongoDB'.format(provider),
                       results_path=results_path, parser=MongodbLogsReader,
                       test_case_name='{}_MongoDB_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype,
                       disk_setup='{} x SSD {}GB RAID0'.format(raid, disk_size))


def test_zookeeper(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                   instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run ZooKeeper benchmark on a tree of 5 servers and 1 generating client.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    vm_count = 6
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=vm_count,
                                                      test_type=None, disk_size=None,
                                                      raid=False, keyid=keyid, secret=secret,
                                                      token=token, subscriptionid=subscription,
                                                      tenantid=tenant, projectid=projectid,
                                                      imageid=imageid, instancetype=instancetype,
                                                      user=user, localpath=localpath,
                                                      region=region, zone=zone, sriov=sriov,
                                                      kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_zookeeper.sh {} {}'.format(user, zk_servers)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'zookeeper{}_{}.zip'.format(str(time.time()),
                                                                               instancetype))
            ssh_client[1].get_file('/tmp/zookeeper.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Zookeeper'.format(provider),
                       results_path=results_path, parser=ZookeeperLogsReader,
                       test_case_name='{}_Zookeeper_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype,
                       cluster_setup='{} x servers'.format(vm_count - 1))


def test_terasort(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                  instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Hadoop terasort benchmark on a tree of servers using 1 master and
    5 slaves instances in VPC to elevate AWS Enhanced Networking.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    vm_count = 6
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=vm_count,
                                                      test_type=constants.CLUSTER_DISK,
                                                      disk_size=50, raid=False, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
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
            cmd = '/tmp/run_terasort.sh {} {} {}'.format(user, device, slaves)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'terasort{}_{}.zip'.format(str(time.time()),
                                                                              instancetype))
            ssh_client[1].get_file('/tmp/terasort.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Terasort'.format(provider),
                       results_path=results_path, parser=TerasortLogsReader,
                       test_case_name='{}_Terasort_perf_tuned'.format(provider),
                       data_path=utils.data_path(sriov), host_type=utils.host_type(provider),
                       instance_size=instancetype,
                       cluster_setup='1 master + {} slaves'.format(vm_count - 1))


def test_storage(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                 instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run FIO storage profile.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    disk_size = 0
    raid = 12
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=1,
                                                      test_type=constants.VM_DISK,
                                                      disk_size=disk_size, raid=raid, keyid=keyid,
                                                      secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
    try:
        if all(client for client in ssh_client.values()):
            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
            ssh_client[1].run('chmod +x /tmp/raid.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/raid.sh")
            ssh_client[1].run('/tmp/raid.sh 0 {} {}'.format(raid, ' '.join(device)))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_storage.sh'),
                                   '/tmp/run_storage.sh')
            ssh_client[1].run('chmod +x /tmp/run_storage.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_storage.sh")
            cmd = '/tmp/run_storage.sh {}'.format(constants.RAID_DEV)
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'storage{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/storage.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Storage'.format(provider),
                       results_path=results_path, parser=StorageLogsReader,
                       test_case_name='{}_Storage_perf_tuned'.format(provider),
                       provider=provider, region=region, data_path=utils.data_path(sriov),
                       host_type=utils.host_type(provider), instance_size=instancetype,
                       disk_setup='RAID0:{}x{}G'.format(raid, disk_size))


def test_network_tcp(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                     instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run NTTTCP network TCP profile.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_network.sh'),
                                   '/tmp/run_network.sh')
            ssh_client[1].run('chmod +x /tmp/run_network.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_network.sh")
            cmd = '/tmp/run_network.sh {} {} {}'.format(vm_ips[2], user, 'TCP')
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'network{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/network.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Network_TCP'.format(provider),
                       results_path=results_path, parser=TCPLogsReader,
                       test_case_name='{}_Network_TCP_perf_tuned'.format(provider),
                       provider=provider, region=region, data_path=utils.data_path(sriov),
                       host_type=utils.host_type(provider), instance_size=instancetype)


def test_network_latency(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                         instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run lagscope network profile.
    :param provider Service provider to be used e.g. azure, aws, gce.
    :param keyid: user key for executing remote connection
    :param secret: user secret for executing remote connection
    :param token: GCE refresh token obtained with gcloud sdk
    :param subscription: Azure specific subscription id
    :param tenant: Azure specific tenant id
    :param projectid: GCE specific project id
    :param imageid: AWS OS AMI image id or
                    Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS'.
    :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
    :param user: remote ssh user for the instance
    :param localpath: localpath where the logs should be downloaded, and the
                        default path for other necessary tools
    :param region: EC2 region to connect to
    :param zone: EC2 zone where other resources should be available
    :param sriov: Enable or disable SR-IOV
    :param kernel: custom kernel name provided in localpath
    """
    connector, vm_ips, device, ssh_client = setup_env(provider=provider, vm_count=2,
                                                      test_type=None, disk_size=None, raid=False,
                                                      keyid=keyid, secret=secret, token=token,
                                                      subscriptionid=subscription, tenantid=tenant,
                                                      projectid=projectid, imageid=imageid,
                                                      instancetype=instancetype, user=user,
                                                      localpath=localpath, region=region,
                                                      zone=zone, sriov=sriov, kernel=kernel)
    results_path = None
    try:
        if all(client for client in ssh_client.values()):
            # enable key auth between instances
            ssh_client[1].put_file(os.path.join(localpath, connector.key_name + '.pem'),
                                   '/home/{}/.ssh/id_rsa'.format(user))
            ssh_client[1].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(user))

            current_path = os.path.dirname(os.path.realpath(__file__))
            ssh_client[1].put_file(os.path.join(current_path, 'tests', 'run_network.sh'),
                                   '/tmp/run_network.sh')
            ssh_client[1].run('chmod +x /tmp/run_network.sh')
            ssh_client[1].run("sed -i 's/\r//' /tmp/run_network.sh")
            cmd = '/tmp/run_network.sh {} {} {}'.format(vm_ips[2], user, 'latency')
            log.info('Running command {}'.format(cmd))
            ssh_client[1].run(cmd)
            results_path = os.path.join(localpath, 'network{}_{}.zip'.format(str(time.time()),
                                                                             instancetype))
            ssh_client[1].get_file('/tmp/network.zip', results_path)
    except Exception as e:
        log.error(e)
        raise
    finally:
        if connector:
            connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_Network_Latency'.format(provider),
                       results_path=results_path, parser=LatencyLogsReader,
                       test_case_name='{}_Network_Latency_perf_tuned'.format(provider),
                       provider=provider, region=region, data_path=utils.data_path(sriov),
                       host_type=utils.host_type(provider), instance_size=instancetype)
