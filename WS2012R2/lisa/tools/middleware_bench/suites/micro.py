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

from utils import constants
from utils import shortcut
from utils.setup import SetupTestEnv

from report.db_utils import upload_results
from report.results_parser import TCPLogsReader, LatencyLogsReader, StorageLogsReader,\
    SingleTCPLogsReader, UDPLogsReader, SchedulerLogsReader

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


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
    elif provider == constants.GCE:
        disk_size = 167

    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=constants.VM_DISK,
                            disk_size=disk_size, raid=raid, keyid=keyid, secret=secret,
                            token=token, subscriptionid=subscription, tenantid=tenant,
                            projectid=projectid, imageid=imageid, instancetype=instancetype,
                            user=user, localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_storage.sh {}'.format(constants.RAID_DEV)
    results_path = os.path.join(localpath, 'storage{}_{}.zip'.format(str(time.time()),
                                                                     instancetype))
    test_env.run_test(testname='storage', test_cmd=test_cmd, raid=raid, results_path=results_path,
                      timeout=constants.TIMEOUT * 2)
    upload_results(localpath=localpath, table_name='Perf_{}_Storage'.format(provider),
                   results_path=results_path, parser=StorageLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Storage_perf_tuned'.format(provider),
                   provider=provider, region=region, data_path=shortcut.data_path(sriov),
                   host_type=shortcut.host_type(provider), instance_size=instancetype,
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
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_network.sh {} {} {}'.format(test_env.vm_ips[2], user, 'TCP')
    results_path = os.path.join(localpath, 'network_tcp_{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='network', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Network_TCP'.format(provider),
                   results_path=results_path, parser=TCPLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Network_TCP_perf_tuned'.format(provider),
                   provider=provider, region=region, data_path=shortcut.data_path(sriov),
                   host_type=shortcut.host_type(provider), instance_size=instancetype)


def test_network_udp(provider, keyid, secret, token, imageid, subscription, tenant, projectid,
                     instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run iperf3 UDP network profile.
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
    test_cmd = '/tmp/run_network.sh {} {} {}'.format(test_env.vm_ips[2], user, 'UDP')
    results_path = os.path.join(localpath, 'network_udp_{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='network', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Network_UDP'.format(provider),
                   results_path=results_path, parser=UDPLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Network_UDP_perf_tuned'.format(provider),
                   provider=provider, region=region, data_path=shortcut.data_path(sriov),
                   host_type=shortcut.host_type(provider), instance_size=instancetype)


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
    test_env = SetupTestEnv(provider=provider, vm_count=2, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_network.sh {} {} {}'.format(test_env.vm_ips[2], user, 'latency')
    results_path = os.path.join(localpath, 'network_latency_{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='network', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Network_Latency'.format(provider),
                   results_path=results_path, parser=LatencyLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Network_Latency_perf_tuned'.format(provider),
                   provider=provider, region=region, data_path=shortcut.data_path(sriov),
                   host_type=shortcut.host_type(provider), instance_size=instancetype)


def test_network_single_tcp(provider, keyid, secret, token, imageid, subscription, tenant,
                            projectid, instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run variable TCP buffer network profile for a single connection.
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
    test_cmd = '/tmp/run_network.sh {} {} {}'.format(test_env.vm_ips[2], user, 'single_tcp')
    results_path = os.path.join(localpath, 'network_single_tcp{}_{}_{}.zip'.format(
            str(time.time()), instancetype, sriov))
    test_env.run_test(ssh_vm_conf=1, testname='network', test_cmd=test_cmd,
                      results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Network_Single_TCP'.format(provider),
                   results_path=results_path, parser=SingleTCPLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Network_Single_TCP_perf_tuned'.format(provider),
                   provider=provider, region=region, data_path=shortcut.data_path(sriov),
                   host_type=shortcut.host_type(provider), instance_size=instancetype)


def test_scheduler(provider, keyid, secret, token, imageid, subscription, tenant,
                   projectid, instancetype, user, localpath, region, zone, sriov, kernel):
    """
    Run kernel scheduler tests.
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
    test_env = SetupTestEnv(provider=provider, vm_count=1, test_type=None, disk_size=None,
                            raid=False, keyid=keyid, secret=secret, token=token,
                            subscriptionid=subscription, tenantid=tenant, projectid=projectid,
                            imageid=imageid, instancetype=instancetype, user=user,
                            localpath=localpath, region=region, zone=zone, sriov=sriov,
                            kernel=kernel)
    test_cmd = '/tmp/run_scheduler.sh {}'.format('all')
    results_path = os.path.join(test_env.localpath, '{}{}_{}.zip'.format(
            'scheduler', str(time.time()), test_env.instancetype))
    test_env.run_test(testname='scheduler', test_cmd=test_cmd, results_path=results_path)
    upload_results(localpath=localpath, table_name='Perf_{}_Scheduler'.format(provider),
                   results_path=results_path, parser=SchedulerLogsReader,
                   other_table=('.deb' in kernel),
                   test_case_name='{}_Scheduler_perf_tuned'.format(provider),
                   host_type=shortcut.host_type(provider), instance_size=instancetype)
