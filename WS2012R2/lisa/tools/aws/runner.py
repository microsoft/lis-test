#!/usr/bin/env python
import argparse
import logging
import sys
import copy
import constants
import connector

from args_validation import TestAction, AWSKeyIdAction, AWSSecretAction, \
    LocalPathAction, RegionAction, ZoneAction, InstTypeAction, ImageIdAction,\
    UserAction

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def run(options):
    """
    Main point of entry for running AWS tests.
    :param options:
            optional arguments:
              -h, --help            show this help message and exit
              -r REGION, --region REGION
                                    AWS specific region to connect to.
              -z ZONE, --zone ZONE  AWS specific zone where to create resources.

            mandatory arguments:
              -t TEST, --test TEST  Test name to be run - defined in
                                    connector.py as a method starting with
                                    'test_*'. E.g.: ['test_orion',
                                    'test_sysbench', 'test_test']
              -k KEYID, --keyid KEYID
                                    AWS access key id.
              -s SECRET, --secret SECRET
                                    AWS secret access key.
              -l LOCALPATH, --localpath LOCALPATH
                                    Local path for saving data.
              -i INSTANCETYPE, --instancetype INSTANCETYPE
                                    AWS instance resource type.
              -g IMAGEID, --imageid IMAGEID
                                    AWS OS AMI image id.
              -u USER, --user USER  AWS instance login username.
    """
    # validate options
    log.info('Options are {}'.format(options))
    sys.stdout.flush()
    parser = argparse.ArgumentParser(description='Run AWS tests.')
    mandatory_args = parser.add_argument_group('mandatory arguments')
    mandatory_args.add_argument(constants.CLI_TEST_OPT_SH,
                                constants.CLI_TEST_OPT, type=str,
                                action=TestAction, required=True,
                                help="Test name to be run - defined in "
                                     "connector.py as a method starting with "
                                     "'test_*'. E.g.: {}".format(
                                    [a for a in dir(connector) if 'test' in a]))
    mandatory_args.add_argument(constants.CLI_AWS_KEYID_OPT_SH,
                                constants.CLI_AWS_KEYID_OPT, type=str,
                                action=AWSKeyIdAction, required=True,
                                help='AWS access key id.')
    mandatory_args.add_argument(constants.CLI_AWS_SECRET_OPT_SH,
                                constants.CLI_AWS_SECRET_OPT, type=str,
                                action=AWSSecretAction, required=True,
                                help='AWS secret access key.')
    mandatory_args.add_argument(constants.CLI_LOCAL_PATH_OPT_SH,
                                constants.CLI_LOCAL_PATH_OPT, type=str,
                                action=LocalPathAction, required=True,
                                help='Local path for saving data.')
    mandatory_args.add_argument(constants.CLI_INST_TYPE_OPT_SH,
                                constants.CLI_INST_TYPE_OPT, type=str,
                                action=InstTypeAction, required=True,
                                help='AWS instance resource type.')
    mandatory_args.add_argument(constants.CLI_IMAGEID_OPT_SH,
                                constants.CLI_IMAGEID_OPT, type=str,
                                action=ImageIdAction, required=True,
                                help='AWS OS AMI image id.')
    mandatory_args.add_argument(constants.CLI_USER_OPT_SH,
                                constants.CLI_USER_OPT, type=str,
                                action=UserAction, required=True,
                                help='AWS instance login username.')
    parser.add_argument(constants.CLI_REGION_OPT_SH, constants.CLI_REGION_OPT,
                        type=str, action=RegionAction,
                        help='AWS specific region to connect to.')
    parser.add_argument(constants.CLI_ZONE_OPT_SH, constants.CLI_ZONE_OPT,
                        type=str, action=ZoneAction,
                        help='AWS specific zone where to create resources.')

    args = parser.parse_args(options)
    log.info('Options are {}'.format(vars(args)))
    test_args = copy.deepcopy(vars(args))
    test_args.pop('test', None)
    getattr(connector, args.test)(**test_args)

if __name__ == "__main__":
    # argv[0] is the script name with the OS location dependent
    run(sys.argv[1:])
