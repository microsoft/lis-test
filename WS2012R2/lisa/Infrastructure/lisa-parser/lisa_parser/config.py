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

import datetime
import argparse
import json
import logging.config
import os


def init_arg_parser():
    arg_parser = argparse.ArgumentParser()

    arg_parser.add_argument(
        "xml_file_path", 
        help="path to the xml config file",
        default=None
    )
    arg_parser.add_argument(
        "log_file_path", 
        help="path to the ica log file",
        default=None
    )
    arg_parser.add_argument(
        "-c", "--config",
        help="path to the config file",
        default=os.path.join(
            os.path.split(os.path.dirname(__file__))[0],
            'config\\db.config'
        )
    )
    arg_parser.add_argument(
        "-l", "--loglevel",
        help="logging level",
        default=2, type=int
    )
    arg_parser.add_argument(
        "-k", "--skipkvp",
        default=False,
        action='store_true',
        help="flag that indicates if commands to the VM are run"
    )
    arg_parser.add_argument(
        "-p", "--perf",
        default=False,
        help="flag that indicates if a performance test is being processed and the"
             "path to the report file"
    )
    arg_parser.add_argument(
        "-s", "--snapshot",
        default=False,
        help="snapshot name of the virtual machine that was tested"
    )
    arg_parser.add_argument(
        "-n", "--nodbcommit",
        default=False,
        action='store_true',
        help="skip commiting results to the database"
    )
    arg_parser.add_argument(
        "-S", "--summary",
        default=False,
        help="Get a summary out of previous reports"
    )
    arg_parser.add_argument(
        "-R", "--report",
        default=False,
        help="Get a report of test coverage and issues on a specific file"
    )

    return arg_parser


def LT_arg_parser():
    arg_parser = argparse.ArgumentParser()

    arg_parser.add_argument(
        "build",
        help="build url",
    )

    arg_parser.add_argument(
        "-t", "--tests",
        help="path to the csv file containing "
             "the test areas and test files",
        default='config/tests.csv'
    )

    arg_parser.add_argument(
        "-r", "--regex",
        help="path to the csv file containing "
             "the database's column names and "
             "the regexes used to extract the "
             "data",
        default='config/regexes.csv'
    )

    arg_parser.add_argument(
        "-c", "--config",
        help="path to the config file",
        default='config/db.config'
    )
    return arg_parser


def validate_input(parsed_arguments):
    message = 'Invalid path to %s file'
    if not os.path.exists(parsed_arguments.xml_file_path):
        return False, message % 'xml'
    elif not os.path.exists(parsed_arguments.log_file_path):
        return False, message % 'log'

    if not os.path.exists(parsed_arguments.config):
        return False, message % 'config'

    if parsed_arguments.perf:
        if not os.path.exists(parsed_arguments.perf):
            return False, message % 'perf'

    return True


def setup_logging(
        default_path='config/log_config.json',
        default_level=logging.INFO,
        env_key='LOG_CFG'
):
    """Setup logging configuration

    """
    if default_level == 1:
        level = logging.WARNING
    elif default_level == 2:
        level = logging.INFO
    elif default_level == 3:
        level = logging.DEBUG
    else:
        level = logging.INFO

    path = default_path
    value = os.getenv(env_key, None)
    log_folder = 'logs'

    if value:
        path = value
    if os.path.exists(path):
        with open(path, 'rt') as log_config:
            config = json.load(log_config)
        if not os.path.exists(log_folder):
            os.makedirs(log_folder)

        info_log_file = \
            config['handlers']['debug_file_handler']['filename'].split('.')

        error_log_file = \
            config['handlers']['error_file_handler']['filename'].split('.')

        config['handlers']['debug_file_handler']['filename'] = \
            os.path.join(log_folder, info_log_file[0] + '-' +
                         datetime.datetime.now()
                         .strftime("%Y-%m-%d_%H-%M-%S") +
                         info_log_file[1])

        config['handlers']['error_file_handler']['filename'] = \
            os.path.join(log_folder, error_log_file[0] + '-' +
                         datetime.datetime.now()
                         .strftime("%Y-%m-%d_%H-%M-%S") +
                         error_log_file[1])

        config['root']['level'] = level

        logging.config.dictConfig(config)
    else:
        logging.basicConfig(level=level)
