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
import sys
import time
import logging

from utils import constants
from utils import shortcut
from utils.cmdshell import WinRMClient
from utils.setup import SetupTestEnv

from report.db_utils import *
from report.results_parser import *

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


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
    elif provider == constants.GCE:
        # pd-ssd 30iops/gb => 167GB = 5010 iops
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=constants.VM_DISK,
                            disk_size=disk_size, raid=False, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_env.ssh_client[1].put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                                    '/tmp/orion_linux_x86-64.gz')
    test_cmd = '/tmp/run_orion.sh {}'.format(test_env.device)
    results_path = os.path.join(localpath, 'orion{}_{}.zip'.format(str(time.time()), instancetype))
    test_env.run_test(testname='orion', test_cmd=test_cmd, results_path=results_path,
                      timeout=constants.TIMEOUT * 5)
    upload_results(localpath=localpath, table_name='Perf_{}_Orion'.format(provider),
                   results_path=results_path, parser=OrionLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Orion_perf_tuned'.format(provider),
                   host_type=shortcut.host_type(provider), instance_size=instancetype,
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
    disk_size = 0
    raid = 10
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=constants.VM_DISK,
                            disk_size=disk_size, raid=raid, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_env.ssh_client[1].put_file(os.path.join(localpath, 'orion_linux_x86-64.gz'),
                                    '/tmp/orion_linux_x86-64.gz')
    test_cmd = '/tmp/run_orion.sh {}'.format(' '.join(test_env.device))
    results_path = os.path.join(localpath, 'orion_raid{}_{}.zip'.format(
            str(time.time()), instancetype))
    test_env.run_test(testname='orion', test_cmd=test_cmd, results_path=results_path, raid=raid,
                      timeout=constants.TIMEOUT * 5)
    upload_results(localpath=localpath, table_name='Perf_{}_Orion'.format(provider),
                   results_path=results_path, parser=OrionLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Orion_perf_tuned'.format(provider),
                   host_type=shortcut.host_type(provider), instance_size=instancetype,
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
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=constants.VM_DISK,
                            disk_size=disk_size, raid=False, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_sysbench.sh {}'.format(test_env.device)
    results_path = os.path.join(localpath, 'sysbench{}_{}.zip'.format(
            str(time.time()), instancetype))
    test_env.run_test(testname='sysbench', test_cmd=test_cmd, results_path=results_path,
                      timeout=constants.TIMEOUT * 5)
    upload_results(localpath=localpath, table_name='Perf_{}_Sysbench'.format(provider),
                   results_path=results_path, parser=SysbenchLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_sysbench_fileio_perf_tuned'.format(provider),
                   host_type=shortcut.host_type(provider), instance_size=instancetype,
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
    disk_size = 0
    raid = 10
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=constants.VM_DISK,
                            disk_size=disk_size, raid=raid, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_sysbench.sh {}'.format(constants.RAID_DEV)
    results_path = os.path.join(localpath, 'sysbench_raid_{}_{}.zip'.format(
            str(time.time()), instancetype))
    test_env.run_test(testname='sysbench', test_cmd=test_cmd, results_path=results_path, raid=raid,
                      timeout=constants.TIMEOUT * 5)
    upload_results(localpath=localpath, table_name='Perf_{}_Sysbench'.format(provider),
                   results_path=results_path, parser=SysbenchLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_sysbench_fileio_perf_tuned'.format(provider),
                   host_type=shortcut.host_type(provider), instance_size=instancetype,
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
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_memcached.sh {} {}'.format(test_env.vm_ips[2], user)
    results_path = os.path.join(localpath, 'memcached{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='memcached', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Memcached'.format(provider),
                   results_path=results_path, parser=MemcachedLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_memcached_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_redis.sh {} {}'.format(test_env.vm_ips[2], user)
    results_path = os.path.join(localpath, 'redis{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='redis', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Redis'.format(provider),
                   results_path=results_path, parser=RedisLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_redis_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_apache_bench.sh {} {}'.format(test_env.vm_ips[2], user)
    results_path = os.path.join(localpath, 'apache_bench{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='apache_bench', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Apache'.format(provider),
                   results_path=results_path, parser=ApacheLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Apache_bench_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_nginx_bench.sh {} {}'.format(test_env.vm_ips[2], user)
    results_path = os.path.join(localpath, 'nginx_bench{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='nginx_bench', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Nginx'.format(provider),
                   results_path=results_path, parser=ApacheLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Apache_bench_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=constants.DB_DISK,
                            disk_size=disk_size, raid=False, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_mariadb.sh {} {} {}'.format(test_env.vm_ips[2], user, test_env.device)
    results_path = os.path.join(localpath, 'mariadb{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='mariadb', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_MariaDB'.format(provider),
                   results_path=results_path, parser=MariadbLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_MariaDB_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    disk_size = 0
    raid = 10
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=constants.DB_DISK,
                            disk_size=disk_size, raid=raid, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_mariadb.sh {} {} {}'.format(test_env.vm_ips[2], user, constants.RAID_DEV)
    results_path = os.path.join(localpath, 'mariadb_raid{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='mariadb', test_cmd=test_cmd, raid=raid, ssh_raid=2,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_MariaDB'.format(provider),
                   results_path=results_path, parser=MariadbLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_MariaDB_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=constants.DB_DISK,
                            disk_size=disk_size, raid=False, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_mongodb.sh {} {} {}'.format(test_env.vm_ips[2], user, test_env.device)
    results_path = os.path.join(localpath, 'mongodb{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='mongodb', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_MongoDB'.format(provider),
                   results_path=results_path, parser=MongodbLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_MongoDB_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    disk_size = 0
    raid = 10
    if provider == constants.AWS:
        disk_size = 100
    elif provider == constants.AZURE:
        disk_size = 513
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=constants.DB_DISK,
                            disk_size=disk_size, raid=raid, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_mongodb.sh {} {} {}'.format(test_env.vm_ips[2], user, constants.RAID_DEV)
    results_path = os.path.join(localpath, 'mongodb_raid{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='mongodb', test_cmd=test_cmd, raid=raid, ssh_raid=2,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_MongoDB'.format(provider),
                   results_path=results_path, parser=MongodbLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_MongoDB_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype,
                   disk_setup='{} x SSD {}GB RAID0'.format(raid, disk_size))


def test_postgresql(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                    instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Pgbench benchmark on PostgreSQL server with a dedicated client.
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
        disk_size = 300
    elif provider == constants.AZURE:
        disk_size = 513
    elif provider == constants.GCE:
        disk_size = 167
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=constants.DB_DISK,
                            disk_size=disk_size, raid=False, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_postgresql.sh {} {} {}'.format(test_env.vm_ips[2], user, test_env.device)
    results_path = os.path.join(localpath, 'postgresql{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='postgresql', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT * 3)
    upload_results(localpath=localpath, table_name='Perf_{}_PostgreSQL'.format(provider),
                   results_path=results_path, parser=PostgreSQLLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_PostgreSQL_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype, disk_setup='1 x SSD {}GB'.format(disk_size))


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
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    zk_servers = ' '.join([test_env.vm_ips[i] for i in range(2, 7)])
    test_cmd = '/tmp/run_zookeeper.sh {} {}'.format(user, zk_servers)
    results_path = os.path.join(localpath, 'zookeeper{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=6, testname='zookeeper', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT)
    upload_results(localpath=localpath, table_name='Perf_{}_Zookeeper'.format(provider),
                   results_path=results_path, parser=ZookeeperLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Zookeeper_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
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
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=constants.CLUSTER_DISK,
                            disk_size=100, raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    slaves = ' '.join([test_env.vm_ips[i] for i in range(2, 7)])
    test_cmd = '/tmp/run_terasort.sh {} {} {}'.format(user, test_env.device, slaves)
    results_path = os.path.join(localpath, 'terasort{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=6, testname='terasort', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT)
    upload_results(localpath=localpath, table_name='Perf_{}_Terasort'.format(provider),
                   results_path=results_path, parser=TerasortLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Terasort_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype,
                   cluster_setup='1 master + {} slaves'.format(vm_count - 1))


def test_sql_server_inmemdb(provider, keyid, secret, token, imageid, subscription, tenant,
                            projectid, instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run SQLServer Benchcraft profiling. The test assumes the existence of a *.vm config file and an
    Azure windows image prepared with all benchcraft prerequisites (sql scripts, ps scripts and
    db flat files). The setup creates a windows and a linux VM for testing specific InMemDB
    performance.
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
        disk_size = 200
    elif provider == constants.AZURE:
        disk_size = 513
    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=constants.VM_DISK,
                            disk_size=disk_size, raid=False, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    results_path = None
    try:
        # TODO add Windows VM support for the other cloud providers
        win_user, password, win_vm = test_env.connector.create_vm(config_file=localpath)
        log.info(win_vm)
        if all(client for client in test_env.ssh_client.values()):
            current_path = os.path.dirname(sys.modules['__main__'].__file__)
            test_env.ssh_client[1].put_file(os.path.join(current_path, 'tests',
                                                         'run_sqlserver.sh'),
                                            '/tmp/run_sqlserver.sh')
            test_env.ssh_client[1].run('chmod +x /tmp/run_sqlserver.sh')
            test_env.ssh_client[1].run("sed -i 's/\r//' /tmp/run_sqlserver.sh")
            cmd = '/tmp/run_sqlserver.sh {} {}'.format(password, constants.DEVICE_AZURE)
            log.info('Running command {}'.format(cmd))
            test_env.ssh_client[1].run(cmd, timeout=constants.TIMEOUT)
            results_path = os.path.join(localpath, 'sqlserver{}_{}_{}.zip'.format(
                    str(time.time()), instancetype, sriov))
            test_env.ssh_client[1].get_file('/tmp/sqlserver.zip', results_path)
            log.info(test_env.ssh_client[1].run('sudo cat /var/opt/mssql/mssql.conf',
                                                timeout=constants.TIMEOUT))
        sqlserver_ip = test_env.vm_ips[1]

        host = win_vm.name + test_env.connector.dns_suffix
        winrm_client = WinRMClient(host=host, user=win_user, password=password)
        settings = []
        sql_sps = []

        settings.append('Set-Content -Value ($(Get-Content {ps_path}Settings.ps1 -raw) -replace \'\$SQLServer = \\\".+\\\"\',\'$SQLServer = \\\"{ip}\\\"\') -Path {ps_path}Settings.ps1'.format(
                ps_path=constants.PS_PATH, ip=sqlserver_ip))
        settings.append('Set-Content -Value ($(Get-Content {ps_path}Settings.ps1 -raw) -replace \'\$SQLPwd = \\\".+\\\"\',\'$SQLPwd = \\\"{passwd}\\\"\') -Path {ps_path}Settings.ps1'.format(
                ps_path=constants.PS_PATH, passwd=password))

        settings.append('Set-Content -Value ($(Get-Content {bc_path}{bc_profile} -raw) -replace \'(?:sqlserver_ip)\',\'{ip}\') -Path {bc_path}{bc_profile}'.format(
                bc_path=constants.BC_PATH, bc_profile=constants.BC_PROFILE, ip=sqlserver_ip))
        settings.append('Set-Content -Value ($(Get-Content {bc_path}{bc_profile} -raw) -replace \'(?:sqlserver_pass)\',\'{passwd}\') -Path {bc_path}{bc_profile}'.format(
                bc_path=constants.BC_PATH, bc_profile=constants.BC_PROFILE, passwd=password))
        for setting in settings:
            log.info(setting)
            winrm_client.run(cmd=setting, ps=True)

        log.info('Creating database.')
        winrm_client.run(cmd=shortcut.run_sql('{}Create_Database_InMem.sql'.format(
                constants.DB_SQL_PATH), sqlserver_ip, password=password), ps=True)
        log.info('Creating InMemDb tables.')
        winrm_client.run(cmd=shortcut.run_sql('{}Create_Tables_InMem.sql'.format(
                constants.DB_SQL_PATH), sqlserver_ip, password=password, db='InMemDb'), ps=True)
        log.info('Loading data into tables.')
        winrm_client.run(cmd='{}Load_HK_DB_BCP.ps1'.format(constants.PS_PATH), ps=True)

        sql_sps.append('{}InMem_FulfillOrders.sql'.format(constants.SP_SQL_PATH))
        sql_sps.append('{}InMem_GetOrdersByCustomerID.sql'.format(constants.SP_SQL_PATH))
        sql_sps.append('{}InMem_GetProductsByType.sql'.format(constants.SP_SQL_PATH))
        sql_sps.append('{}InMem_GetProductsPriceByPK.sql'.format(constants.SP_SQL_PATH))
        sql_sps.append('{}InMem_InsertOrder.sql'.format(constants.SP_SQL_PATH))
        sql_sps.append('{}InMem_ProductSelectionCriteria.sql'.format(constants.SP_SQL_PATH))
        sql_sps.append('{}optimize_memory.sql'.format(constants.DB_SCRIPTS_PATH))
        for sql_sp in sql_sps:
            log.info(sql_sp)
            winrm_client.run(cmd=shortcut.run_sql(sql_sp, sqlserver_ip, password=password,
                                                  db='InMemDb'), ps=True)

        # start server collect
        test_env.ssh_client[1].run('mkdir /tmp/sqlserver_stats', timeout=constants.TIMEOUT)
        test_env.ssh_client[1].run('nohup sar -n DEV 1 > /tmp/sqlserver_stats/sar.netio.log 2>&1 &',
                                   timeout=constants.TIMEOUT)
        test_env.ssh_client[1].run('nohup iostat -x -d 1 > /tmp/sqlserver_stats/iostat.diskio.log 2>&1 &',
                                   timeout=constants.TIMEOUT)
        test_env.ssh_client[1].run('nohup vmstat 1 > /tmp/sqlserver_stats/vmstat.memory.cpu.log 2>&1 &',
                                   timeout=constants.TIMEOUT)

        cmd = '{bc_path}start.ps1'.format(bc_path=constants.BC_PATH)
        log.info(cmd)
        winrm_client.run(cmd=cmd, ps=True)

        # collect server stats
        test_env.ssh_client[1].run('pkill -f sar; pkill -f vmstat; pkill -f iostat',
                                   timeout=constants.TIMEOUT)
        test_env.ssh_client[1].run('cd /tmp; zip -r sqlserver_stats.zip . -i sqlserver_stats/*',
                                   timeout=constants.TIMEOUT)
        test_env.ssh_client[1].get_file('/tmp/sqlserver_stats.zip', os.path.join(
                localpath, 'sqlserver_stats{}_{}.zip'.format(str(time.time()), instancetype)))

        cmd = 'type {}Report1.log'.format(constants.BC_PATH)
        report = winrm_client.run(cmd=cmd, ps=True)
    except Exception as e:
        log.exception(e)
        raise
    finally:
        if test_env.connector:
            test_env.connector.teardown()
    if results_path:
        upload_results(localpath=localpath, table_name='Perf_{}_SQLServer'.format(provider),
                       results_path=results_path, parser=SQLServerLogsReader,
                       other_table=('.deb' in kernel),
                       test_case_name='{}_SQLServer_perf_tuned'.format(provider),
                       provider=provider, region=region, data_path=shortcut.data_path(sriov),
                       host_type=shortcut.host_type(provider), instance_size=instancetype,
                       disk_setup='1 x SSD {}GB'.format(disk_size), report=report)

def test_lamp_wordpress(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                  instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Apache Benchmark on LAMP+Wordpress server.
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
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=None,
                            disk_size=None, raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    software_bundle = 'lamp'
    test_cmd = '/tmp/run_wordpress.sh {} {} {}'.format(test_env.vm_ips[2], user, software_bundle)
    current_path = os.getcwd()
    results_path = os.path.join(localpath, 'lamp_wordpress{}_{}_{}.zip'.format(str(time.time()), instancetype, sriov))    
    test_env.ssh_client[2].put_file(os.path.join(current_path, 'tests', 'install_lamp_wordpress.sh'), '/tmp/install_lamp_wordpress.sh')
    test_env.ssh_client[2].run('chmod +x /tmp/install_lamp_wordpress.sh')
    test_env.ssh_client[2].run("sed -i 's/\r//' /tmp/install_lamp_wordpress.sh")
    test_env.run_test(ssh_vm_conf=1, testname='wordpress', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT * 5)
    upload_results(localpath=localpath, table_name='Perf_{}_LAMP_Wordpress'.format(provider),
                   results_path=results_path, parser=LAMPWordpressLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_LAMP_Wordpress_perf'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype)

def test_lemp_wordpress(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                  instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Apache Benchmark on LEMP+Wordpress server.
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
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=None,
                            disk_size=None, raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    software_bundle = 'lemp'
    test_cmd = '/tmp/run_wordpress.sh {} {} {}'.format(test_env.vm_ips[2], user, software_bundle)
    current_path = os.getcwd()
    results_path = os.path.join(localpath, 'lemp_wordpress{}_{}_{}.zip'.format(str(time.time()), instancetype, sriov))    
    test_env.ssh_client[2].put_file(os.path.join(current_path, 'tests', 'install_lemp_wordpress.sh'), '/tmp/install_lemp_wordpress.sh')
    test_env.ssh_client[2].run('chmod +x /tmp/install_lemp_wordpress.sh')
    test_env.ssh_client[2].run("sed -i 's/\r//' /tmp/install_lemp_wordpress.sh")
    test_env.run_test(ssh_vm_conf=1, testname='wordpress', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT * 5)
    upload_results(localpath=localpath, table_name='Perf_{}_LEMP_Wordpress'.format(provider),
                   results_path=results_path, parser=LAMPWordpressLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_LEMP_Wordpress_perf'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype)

def test_nodejs(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                  instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run Web tooling benchmark use Nodejs.
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
    vm_count = 1
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=None,
                            disk_size=None, raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_nodejs.sh'
    current_path = os.path.dirname(os.path.realpath(__file__))
    results_path = os.path.join(localpath, 'nodejs{}_{}_{}.zip'.format(str(time.time()), instancetype, sriov))    
    test_env.run_test(testname='nodejs', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT)
    upload_results(localpath=localpath, table_name='Perf_{}_Nodejs'.format(provider),
                   results_path=results_path, parser=NodejsLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Nodejs_perf'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype)

def test_kafka(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                   instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run kafka benchmark on a tree of one Zookeeper Node and 3 Broker Nodes server and 1 Jumpbox.
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
    vm_count = 5
    if provider == constants.AWS:
        disk_size = 1023
    elif provider == constants.AZURE:
        disk_size = 1023
    elif provider == constants.GCE:
        disk_size = 500
    test_env = SetupTestEnv(provider=provider, vm_count=vm_count, test_type=constants.CLUSTER_DISK, disk_size=disk_size,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    zk_servers = ' '.join([test_env.vm_ips[i] for i in range(2, 6)])
    test_cmd = '/tmp/run_kafka.sh {} {} {}'.format(user, test_env.device, zk_servers)
    results_path = os.path.join(localpath, 'kafka{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=5, testname='kafka', test_cmd=test_cmd,
                      results_path=results_path, timeout=constants.TIMEOUT * 2)
    upload_results(localpath=localpath, table_name='Perf_{}_Kafka'.format(provider),
                   results_path=results_path, parser=KafkaLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Kafka_perf_tuned'.format(provider),
                   data_path=shortcut.data_path(sriov), host_type=shortcut.host_type(provider),
                   instance_size=instancetype,
                   cluster_setup='1 zookeeper + {} brokers'.format(vm_count - 2))
