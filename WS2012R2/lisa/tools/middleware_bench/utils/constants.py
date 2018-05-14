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

LOG_FORMAT = '%(asctime)s %(levelname)s: %(message)s'
LOG_DATE_FORMAT = '%y/%m/%d %H:%M:%S'

CLI_TEST_OPT = '--test'
CLI_TEST_OPT_SH = '-t'
CLI_PROVIDER_OPT = '--provider'
CLI_PROVIDER_OPT_SH = '-p'

CLI_AWS_KEYID_OPT = '--keyid'
CLI_AWS_KEYID_OPT_SH = '-k'
CLI_AWS_SECRET_OPT = '--secret'
CLI_AWS_SECRET_OPT_SH = '-s'

CLI_KEYID_OPT = '--keyid'
CLI_KEYID_OPT_SH = '-k'
CLI_SECRET_OPT = '--secret'
CLI_SECRET_OPT_SH = '-s'
CLI_SUBSCRIPTION_OPT = '--subscription'
CLI_SUBSCRIPTION_OPT_SH = '-b'
CLI_TENANT_OPT = '--tenant'
CLI_TENANT_OPT_SH = '-n'
CLI_PROJECTID_OPT = '--projectid'
CLI_PROJECTID_OPT_SH = '-j'
CLI_TOKEN_OPT = '--token'
CLI_TOKEN_OPT_SH = '-o'

CLI_LOCAL_PATH_OPT = '--localpath'
CLI_LOCAL_PATH_OPT_SH = '-l'
CLI_REGION_OPT = '--region'
CLI_REGION_OPT_SH = '-r'
CLI_ZONE_OPT = '--zone'
CLI_ZONE_OPT_SH = '-z'
CLI_INST_TYPE_OPT = '--instancetype'
CLI_INST_TYPE_OPT_SH = '-i'
CLI_IMAGEID_OPT = '--imageid'
CLI_IMAGEID_OPT_SH = '-g'
CLI_USER_OPT = '--user'
CLI_USER_OPT_SH = '-u'
CLI_SRIOV_OPT = '--sriov'
CLI_SRIOV_OPT_SH = '-sr'
CLI_KERNEL_OPT = '--kernel'
CLI_KERNEL_OPT_SH = '-kr'
CLI_SUITE_OPT = '--suite'
CLI_SUITE_OPT_SH = '-su'

AWS = 'aws'
AZURE = 'azure'
GCE = 'gce'

HVM = 'hvm'
MSAZURE = 'MS Azure'
KVM = 'kvm'

SYNTHETIC_TESTS = ['test_orion', 'test_orion_raid', 'test_sysbench', 'test_sysbench_raid',
                   'test_scheduler', 'test_storage', 'test_tensorflow_gpu', 'test_tensorflow_cpu', 'test_nodejs', 'test_elasticsearch']
AZURE_TESTS = ['test_sql_server_inmemdb']
NOT_GCE_TESTS = ['test_tensorflow_gpu']
# GCE doesn't have quota for gpu

DEVICE_AWS = '/dev/sdx'
DEVICE_AZURE = '/dev/sdc'
DEVICE_GCE = '/dev/disk/by-id/google-'
TEMP_DEVICE_GCE = '/dev/sdb'

AWS_P28XLARGE = 'p2.8xlarge'
AWS_D24XLARGE = 'd2.4xlarge'
AWS_M416XLARGE = 'm4.16xlarge'

VM_DISK = 'vm_disk'
DB_DISK = 'db_disk'
CLUSTER_DISK = 'cluster_disk'

RAID_DEV = '/dev/md0'

ENABLED = 'enabled'
SRIOV = 'SRIOV'
SYNTHETIC = 'Synthetic'

# timeout in seconds; default 3h
TIMEOUT = 3 * 60 * 60

# SQL Server constants
MSSQL_USER = 'sa'
PS_PATH = 'C:\\\\inmemdb\\\\Data_Generator\\\\PS_scripts\\\\'
BC_PATH = 'C:\\\\inmemdb\\\\Benchcraft\\\\'
DB_SCRIPTS_PATH = 'C:\\inmemdb\\Database_Scripts\\'
DB_SQL_PATH = DB_SCRIPTS_PATH + 'create-database-and-tables\\In-Memory\\'
SP_SQL_PATH = DB_SCRIPTS_PATH + 'stored-procedures\\Native\\'
BC_PROFILE = 'inmemdb.bp'
