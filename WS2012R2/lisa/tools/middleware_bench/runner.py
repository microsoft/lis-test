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
import os
import sys
import copy
import argparse
import logging
import pkgutil
import importlib

from junit_xml import TestSuite, TestCase

import suites
from utils import constants

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def run(options):
    """
    Main point of entry for running benchmark tests.
    """
    sys.stdout.flush()
    # lookup suites and tests
    suite_names = [suite for _, suite, _ in pkgutil.iter_modules(suites.__path__)]
    test_names = {}
    for suite in suite_names:
        test_names[suite] = [test
                             for test in dir(importlib.import_module('suites.{}'.format(suite)))
                             if 'test_' in test]
    # validate options
    parser = argparse.ArgumentParser(description='Run middleware benchmarking tests.')
    mandatory_args = parser.add_argument_group('mandatory arguments')
    mandatory_args.add_argument(constants.CLI_SUITE_OPT_SH, constants.CLI_SUITE_OPT,
                                type=str, default='specific',
                                help='Provide suite to execute. Defaults to "specific" when '
                                     '"--test" arg is used to execute specific tests.'
                                     'Suites available: {}'.format(
                                        [suite for suite in suite_names]))
    mandatory_args.add_argument(constants.CLI_TEST_OPT_SH, constants.CLI_TEST_OPT,
                                type=str, default='all',
                                help='When using "--suite specific", a test name or a comma '
                                     'separated list of tests must be provided for execution. '
                                     'Tests available: {}'.format(
                                        [test for suite in suite_names
                                         for test in test_names[suite]]))
    mandatory_args.add_argument(constants.CLI_PROVIDER_OPT_SH, constants.CLI_PROVIDER_OPT,
                                type=str, required=True,
                                help='Service provider to be used e.g. azure/aws/gce.')
    mandatory_args.add_argument(constants.CLI_KEYID_OPT_SH, constants.CLI_KEYID_OPT,
                                type=str, required=True, help='Azure/aws/gce key id.')
    mandatory_args.add_argument(constants.CLI_SECRET_OPT_SH, constants.CLI_SECRET_OPT,
                                type=str, required=True, help='Azure/aws/gce client secret.')
    mandatory_args.add_argument(constants.CLI_LOCAL_PATH_OPT_SH, constants.CLI_LOCAL_PATH_OPT,
                                type=str, required=True, help='Local path for saving data.')
    mandatory_args.add_argument(constants.CLI_INST_TYPE_OPT_SH, constants.CLI_INST_TYPE_OPT,
                                type=str, required=True,
                                help='Azure/aws/gce instance size e.g. "Standard_DS1".')
    mandatory_args.add_argument(constants.CLI_IMAGEID_OPT_SH, constants.CLI_IMAGEID_OPT,
                                type=str, required=True,
                                help='Azure/aws/gce image id or os version e.g. '
                                     '"UbuntuServer#16.04.0-LTS".')
    mandatory_args.add_argument(constants.CLI_USER_OPT_SH, constants.CLI_USER_OPT,
                                type=str, required=True, help='Instance login user.')

    parser.add_argument(constants.CLI_TOKEN_OPT_SH, constants.CLI_TOKEN_OPT,
                        type=str, default='', help='GCE refresh token.')
    parser.add_argument(constants.CLI_SUBSCRIPTION_OPT_SH, constants.CLI_SUBSCRIPTION_OPT,
                        type=str, default='', help='Azure subscription id.')
    parser.add_argument(constants.CLI_TENANT_OPT_SH, constants.CLI_TENANT_OPT,
                        type=str, default='', help='Azure tenant id.')
    parser.add_argument(constants.CLI_PROJECTID_OPT_SH, constants.CLI_PROJECTID_OPT,
                        type=str, default='', help='GCE project id.')
    parser.add_argument(constants.CLI_REGION_OPT_SH, constants.CLI_REGION_OPT,
                        type=str, default='', help='Azure/aws/gce region to connect to.')
    parser.add_argument(constants.CLI_ZONE_OPT_SH, constants.CLI_ZONE_OPT,
                        type=str, default='',
                        help='Aws/gce specific zone where to create resources e.g. us-west1-a.')
    parser.add_argument(constants.CLI_SRIOV_OPT_SH, constants.CLI_SRIOV_OPT,
                        type=str, default='disabled', help='Enabled/disabled SRIOV feature.')
    parser.add_argument(constants.CLI_KERNEL_OPT_SH, constants.CLI_KERNEL_OPT,
                        type=str, default='', help='Kernel to install from localpath.')

    args = parser.parse_args(options)
    test_args = copy.deepcopy(vars(args))
    current_suite = test_args['suite']
    test_args.pop('suite', None)
    current_tests = test_args['test']
    test_args.pop('test', None)
    junit_testcases = []
    if current_suite == 'specific':
        selected_tests = current_tests.split(',')
        all_tests = [t for s in test_names.values() for t in s]
        if not all(sel_test in all_tests for sel_test in selected_tests):
            raise Exception('Could not validated all the "specific" tests provided. '
                            'Use "runner.py -h" to list all the currently supported tests.')
        log.info('Tests to run: {}'.format(selected_tests))
        for test in selected_tests:
            log.info('Running test: {}'.format(test))
            try:
                module = [k for k, v in test_names.items() if test in v][0]
                getattr(importlib.import_module('suites.{}'.format(module)), test)(**test_args)
            except Exception as e:
                junit_testcase = TestCase(test)
                junit_testcase.add_failure_info(e)
                junit_testcases.append(junit_testcase)
                continue
            junit_testcases.append(TestCase(test))
    else:
        log.info('Suite to run: {}'.format(current_suite))
        if not test_names.get(current_suite, None):
            raise Exception('Suite {} not defined. Use "runner.py -h" to list all '
                            'supported suites.'.format(current_suite))
        for test in test_names[current_suite]:
            if test_args['provider'] == constants.AZURE and\
                    test_args['sriov'] == constants.ENABLED and test in constants.SYNTHETIC_TESTS:
                log.info('Skipping synthetic test: {}, for SRIOV enabled.'.format(test))
                continue
            else:
                log.info('Running test: {}'.format(test))
            try:
                getattr(importlib.import_module('suites.{}'.format(current_suite)),
                        test)(**test_args)
            except Exception as e:
                junit_testcase = TestCase(test)
                junit_testcase.add_failure_info(e)
                junit_testcases.append(junit_testcase)
                continue
            junit_testcases.append(TestCase(test))

    # generate junit xml
    junit_suite = [TestSuite(current_suite, junit_testcases)]
    with open(os.path.join(test_args['localpath'], 'junit_{}.xml'.format(current_suite)),
              mode='w') as f:
        TestSuite.to_file(f, junit_suite, prettyprint=False)


if __name__ == "__main__":
    # argv[0] is the script name with the OS location dependent
    run(sys.argv[1:])
