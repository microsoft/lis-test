#!/usr/bin/env python
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
import argparse
import logging
import sys
import copy
import constants
import connector

from args_validation import TestAction, ProviderAction, KeyIdAction, SecretAction,\
    SubscriptionAction, TenantAction, LocalPathAction, RegionAction, ZoneAction, InstTypeAction,\
    ImageIdAction, UserAction, ProjectAction, TokenAction, KernelAction, SriovAction

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def run(options):
    """
    Main point of entry for running middleware benchmarking tests.
    :param options:
            optional arguments:
              -h, --help
                        show this help message and exit
              -r REGION, --region REGION
                        AWS specific region or
                        Azure specific location to connect to.
              -z ZONE, --zone ZONE
                        AWS specific zone where to create resources o
                        GCE specific zone e.g. us-west1-a
              -b SUBSCRIPTION, --subscription SUBSCRIPTION
                        Azure specific subscription id.
              -n TENANT, --tenant TENANT
                        Azure tenant id.
              -j PROJECTID, --project PROJECTID
                        GCE project ID
              -o TOKEN, --token TOKEN
                        GCE refresh token obtained with gcloud sdk.
              -sr SRIOV, --sriov SRIOV
                        Bool to enable or disable SRIOV.
              -kr KERNEL, --kernel KERNEL
                        Custom kernel to install from localpath.

            mandatory arguments:
              -t TEST, --test TEST
                        Test name to be run - defined in connector.py as a method starting with
                        'test_*'. E.g.: ['test_orion', 'test_sysbench', 'test_test']
              -p PROVIDER, --provider PROVIDER
                        Service provider to be used e.g. azure, aws, gce.
              -k KEYID, --keyid KEYID
                        AWS access key id or Azure client id.
              -s SECRET, --secret SECRET
                        AWS secret access key or Azure client secret.
              -l LOCALPATH, --localpath LOCALPATH
                        Local path for saving data.
              -i INSTANCETYPE, --instancetype INSTANCETYPE
                        AWS instance resource type or
                        Azure hardware profile vm size e.g. 'Standard_DS14_v2'.
              -g IMAGEID, --imageid IMAGEID
                        AWS OS AMI image id or
                        Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS' or
                        GCE image family e.g. 'ubuntu-1604-lts'
              -u USER, --user USER
                        Instance/VM login username.
    """
    # validate options
    log.info('Options are {}'.format(options))
    sys.stdout.flush()
    parser = argparse.ArgumentParser(description='Run middleware benchmarking tests.')
    mandatory_args = parser.add_argument_group('mandatory arguments')
    mandatory_args.add_argument(constants.CLI_TEST_OPT_SH,
                                constants.CLI_TEST_OPT, type=str,
                                action=TestAction, required=True,
                                help="Test name to be run - defined in "
                                     "connector.py as a method starting with "
                                     "'test_*'. E.g.: {}".format(
                                        [a for a in dir(connector) if 'test' in a]))
    mandatory_args.add_argument(constants.CLI_PROVIDER_OPT_SH,
                                constants.CLI_PROVIDER_OPT, type=str,
                                action=ProviderAction, required=True,
                                help='Service provider to be used e.g. azure, middleware_bench, '
                                     'gce.')
    mandatory_args.add_argument(constants.CLI_KEYID_OPT_SH,
                                constants.CLI_KEYID_OPT, type=str,
                                action=KeyIdAction, required=True,
                                help='AWS access key id or Azure client id.')
    mandatory_args.add_argument(constants.CLI_SECRET_OPT_SH,
                                constants.CLI_SECRET_OPT, type=str,
                                action=SecretAction, required=True,
                                help='AWS secret access key or Azure client secret.')
    mandatory_args.add_argument(constants.CLI_LOCAL_PATH_OPT_SH,
                                constants.CLI_LOCAL_PATH_OPT, type=str,
                                action=LocalPathAction, required=True,
                                help='Local path for saving data.')
    mandatory_args.add_argument(constants.CLI_INST_TYPE_OPT_SH,
                                constants.CLI_INST_TYPE_OPT, type=str,
                                action=InstTypeAction, required=True,
                                help='AWS instance resource type or'
                                     'Azure hardware profile vm size e.g. "Standard_DS1".')
    mandatory_args.add_argument(constants.CLI_IMAGEID_OPT_SH,
                                constants.CLI_IMAGEID_OPT, type=str,
                                action=ImageIdAction, required=True,
                                help='AWS OS AMI image id or'
                                     'Azure image references offer and sku:'
                                     'e.g. "UbuntuServer#16.04.0-LTS".')
    mandatory_args.add_argument(constants.CLI_USER_OPT_SH,
                                constants.CLI_USER_OPT, type=str,
                                action=UserAction, required=True,
                                help='Instance/VM login username.')

    parser.add_argument(constants.CLI_TOKEN_OPT_SH,
                        constants.CLI_TOKEN_OPT, type=str,
                        action=TokenAction,
                        help='GCE refresh token obtained with gcloud sdk.')
    parser.add_argument(constants.CLI_SUBSCRIPTION_OPT_SH,
                        constants.CLI_SUBSCRIPTION_OPT, type=str,
                        action=SubscriptionAction,
                        help='Azure specific subscription id.')
    parser.add_argument(constants.CLI_TENANT_OPT_SH,
                        constants.CLI_TENANT_OPT, type=str,
                        action=TenantAction,
                        help='Azure specific tenant id.')
    parser.add_argument(constants.CLI_PROJECTID_OPT_SH, constants.CLI_PROJECTID_OPT,
                        type=str, action=ProjectAction,
                        help='GCE project id.')
    parser.add_argument(constants.CLI_REGION_OPT_SH, constants.CLI_REGION_OPT,
                        type=str, action=RegionAction,
                        help='AWS specific region to connect to or '
                             'Azure specific location to connect to.')
    parser.add_argument(constants.CLI_ZONE_OPT_SH, constants.CLI_ZONE_OPT,
                        type=str, action=ZoneAction,
                        help='AWS specific zone where to create resources or '
                             'GCE specific zone e.g. us-west1-a.')
    parser.add_argument(constants.CLI_SRIOV_OPT_SH, constants.CLI_SRIOV_OPT,
                        type=str, action=SriovAction,
                        help='Bool to enable or disable SRIOV.')
    parser.add_argument(constants.CLI_KERNEL_OPT_SH, constants.CLI_KERNEL_OPT,
                        type=str, action=KernelAction,
                        help='Custom kernel to install from localpath.')

    args = parser.parse_args(options)
    log.info('Options are {}'.format(vars(args)))
    test_args = copy.deepcopy(vars(args))
    test_args.pop('test', None)
    getattr(connector, args.test)(**test_args)

if __name__ == "__main__":
    # argv[0] is the script name with the OS location dependent
    run(sys.argv[1:])
