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

from __future__ import print_function

import logging
import sys

from envparse import env

import sql_utils
import config
from test_run import PerfTestRun
from test_run import TestRun

logger = logging.getLogger(__name__)


def main(args):
    """The main entry point of the application

    The script follows a simple workflow in order to parse and persist
    the test run information to a database. It runs the main logic under a
    TestRun/PerfTestRun object designed to encapsulate information for a
    specific test run.

    The parser expects at least two arguments, an xml and a log file, in order
    to parse minimum information regarding the tests that have been run and
    the test environment.
    """
    # Parse arguments and check if they exist
    arg_parser = config.init_arg_parser()
    parsed_arguments = arg_parser.parse_args(args)

    path_validation = config.validate_input(parsed_arguments)
    if isinstance(path_validation, list):
        print("\n%s \n" % path_validation[1])
        print(arg_parser.parse_args(['-h']))
        sys.exit(0)

    config.setup_logging(
        default_level=int(parsed_arguments.loglevel)
    )

    logger.debug('Parsing env variables')
    env.read_envfile(parsed_arguments.config)

    logger.info('Initializing TestRun object')
    if parsed_arguments.perf:
        test_run = PerfTestRun(parsed_arguments.perf,
                               parsed_arguments.skipkvp,
                               parsed_arguments.snapshot)
    else:
        test_run = TestRun(
            skip_vm_check=parsed_arguments.skipkvp,
            checkpoint_name=parsed_arguments.snapshot
        )

    logger.info('Parsing XML file - %s', parsed_arguments.xml_file_path)
    test_run.update_from_xml(parsed_arguments.xml_file_path)

    logger.info('Parsing log file - %s', parsed_arguments.log_file_path)
    test_run.update_from_ica(parsed_arguments.log_file_path)

    if not parsed_arguments.skipkvp:
        logger.info('Getting KVP values from VM')
        test_run.update_from_vm([
            'OSBuildNumber', 'OSName', 'OSMajorVersion'
        ], stop_vm=True)

    # Parse values to be inserted
    logger.info('Parsing test run for database insertion')
    insert_values = test_run.parse_for_db_insertion()
    # Connect to db and insert values in the table
    logger.info('Initializing database connection')
    db_connection, db_cursor = sql_utils.init_connection()

    logger.info('Executing insertion commands')
    for table_line in insert_values:
        sql_utils.insert_values(db_cursor, table_line)

    logger.info('Committing changes to the database')
    db_connection.commit()

    logger.info("Checking insert validity")
    sql_utils.check_insert(db_cursor, insert_values)

if __name__ == '__main__':
    main(sys.argv[1:])

