import sys
import copy
import argparse
import importlib

sys.path.append('../')
import suites

def Run(option):
    parser = argparse.ArgumentParser(description="Get all cases name in the specified suite")
    parser.add_argument('-su', '--suite',
                    type=str, required=True,
                    help='Provide suite to execute') 
    args = parser.parse_args(option)
    test_args = copy.deepcopy(vars(args))
    suite = test_args['suite']
    test_names = [test
                  for test in dir(importlib.import_module('suites.{}'.format(suite)))
                  if 'test_' in test]
    print ','.join(test_names)

Run(sys.argv[1:])
