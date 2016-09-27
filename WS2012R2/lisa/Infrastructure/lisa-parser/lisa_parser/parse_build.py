import csv
import logging
import os
import re
import sys
from urllib2 import urlopen

from envparse import env

import sql_utils
from lisa_parser import config

logger = logging.getLogger(__file__.split('/')[-1])


def add_get_function(regex, content):
    def inner():
        try:
            aux = re.search(regex, content)
            return aux.group(0)
        except:
            return "None"
    return inner


class Parser:
    def __init__(self, *args):
        config.setup_logging()
        args = args[0]
        arg_parser = config.LT_arg_parser()
        parsed_arguments = arg_parser.parse_args(args)
        env.read_envfile(parsed_arguments.config)

        self.url = parsed_arguments.build
        self.functions = {}
        self.regexes = {}

        self.content = urlopen(self.url + "consoleText").read()
        self.suite_tests = self.compute_tests(parsed_arguments.tests)
        self.parse_regexes(parsed_arguments.regex)
        self.suite = re.search('(?<=job/)\D+/', self.url).group(0)[:-1]

        for function_name, regex in self.regexes.items():
            function = add_get_function(regex, self.content)
            setattr(self, "get_" + function_name, function)
            self.functions[function_name] = function

    def parse_regexes(self, regex_file):
        path = os.path.dirname(__file__)
        file = open(os.path.join(path, regex_file), 'r')
        reader = csv.reader(file, delimiter=',')
        for line in reader:
            self.regexes[line[0]] = line[1]
        file.close()

    @staticmethod
    def compute_tests(test_file):
        path = os.path.dirname(__file__)
        test_file = open(os.path.join(path, test_file), 'r')
        reader = csv.reader(test_file, delimiter=',')
        tests = {}
        for line in reader:
            try:
                tests[line[0]].append(line[1])
            except KeyError:
                tests[line[0]] = []
                tests[line[0]].append(line[1])
            except IndexError:
                pass
        test_file.close()
        return tests

    def get_results(self):
        results = {}
        tests = self.suite_tests[self.suite]
        for test in tests:
            try:
                aux = re.search(".*Test " + test + " :( )+ \w+", self.content).group(0)
                result = re.compile("\w+").findall(aux)[-1]
                results[test] = result
            except Exception:
                results[test] = "Failed"
        return results

    def process_entry(self):
        line = {}
        for key in self.functions:
            line[key] = self.functions[key]()
        return line

    @staticmethod
    def parse_build():

        db_connection, db_cursor = sql_utils.init_connection()
        logger.info("Successfully connected to Database")

        results = parser.get_results()
        logger.info("Successfully parsed the results")

        try:
            for result in results:
                d = parser.process_entry()
                d['TestCaseName'] = result
                d['TestResult'] = results[result]
                d['TestLocation'] = "Hyper-V"
                sql_utils.insert_values(db_cursor, d)
            db_connection.commit()
        except Exception as e:
            logger.error(e[1])
        else:
            logger.info("Successfully added to database!")

if __name__ == "__main__":
    parser = Parser(sys.argv[1:])
    parser.parse_build()
