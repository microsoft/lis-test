import os
import sys
import copy
import argparse
import logging
import pkgutil
import importlib

sys.path.append('../')
import suites

def Run(option):
    parser = argparse.ArgumentParser(description="Flip a switch by setting a flag")
    parser.add_argument('-su', '--suite',
                    type=str, required=True,
                    help='Provide suite to execute. Defaults to "specific"')
    parser.add_argument('-ls', '--list', action='store_true', help='if True, list all the cases name in the specified suite')

    args = parser.parse_args(option)
    test_args = copy.deepcopy(vars(args))
    suite = test_args['suite']
    test_names = [test
                  for test in dir(importlib.import_module('suites.{}'.format(suite)))
                  if 'test_' in test]
    list_result = test_args['list']
    if list_result:
        print ','.join(test_names)

Run(sys.argv[1:])
