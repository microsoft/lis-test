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
import re
import sys
import csv
import fileinput

try:
    import xml.etree.cElementTree as ElementTree
except ImportError:
    import xml.etree.ElementTree as ElementTree


logger = logging.getLogger(__name__)


class ParseXML(object):
    """Class used to parse a specific xml test suite file

    """
    def __init__(self, file_path):
        self.tree = ElementTree.ElementTree(file=file_path)
        self.root = self.tree.getroot()

    def get_tests_suite(self):
        return self.root.find('testSuites').getchildren()[0]\
            .find('suiteName').text

    def get_tests(self):
        """Iterates through the xml file looking for <test> sections

         and initializes a dict for every test case returning them in
         the end

         Dict structure:
            { 'testName' : {} }
        """
        tests_dict = dict()

        for test in self.root.iter('suiteTest'):
            tests_dict[test.text.lower()] = dict()

            for test_case in self.root.iter('test'):
                # Check if testCase was not commented out
                if test_case.find('testName').text.lower() == \
                        test.text.lower():
                    logger.debug('Getting test details for - %s', test.text)
                    tests_dict[test.text.lower()] = \
                        self.get_test_details(test_case)

        return tests_dict

    @staticmethod
    def get_test_details(test_root):
        """Gets and an XML object and iterates through it

         parsing the test details into a dictionary

         Dict structure:
            { 'testProperty' : [ value(s) ] }
        """

        test_dict = dict()
        for test_property in test_root.getchildren():
            if test_property.tag == 'testName':
                continue
            elif not test_property.getchildren() and test_property.text:
                test_dict[test_property.tag.lower()] = \
                    test_property.text.strip().split()
            else:
                test_dict[test_property.tag.lower()] = list()
                for item in test_property.getchildren():
                    if test_property.tag.lower() == 'testparams':
                        parameter = item.text.split('=')
                        test_dict[test_property.tag.lower()].append(
                            (parameter[0], parameter[1])
                        )
                    else:
                        test_dict[test_property.tag.lower()].append(item.text)

        return test_dict

    def get_vms(self):
        """Method searches for the 'vm' sections in the XML file

        saving a dict for each vm found.
        Dict structure:
        {
            vm_name: { vm_details }
        }
        """
        vm_dict = dict()
        for machine in self.root.iter('vm'):
            vm_dict[machine.find('vmName').text.lower()] = {
                'hvServer': machine.find('hvServer').text.lower(),
                'os': machine.find('os').text.lower()
            }

        return vm_dict

    # TODO(bogdancarpusor): Narrow exception field
    @staticmethod
    def parse_from_string(xml_string):
        """Static method that parses xml content from a string

        The method is used to parse the output of the PS command
        that is sent to the vm in order to get more details

        It returns a dict with the following structure:
        {
            vm_property: value
        }
        """
        try:
            logger.debug('Converting XML string from KVP Command')
            root = ElementTree.fromstring(xml_string.strip())
            prop_name = ''
            prop_value = ''
            for child in root:
                if child.attrib['NAME'] == 'Name':
                    prop_name = child[0].text
                elif child.attrib['NAME'] == 'Data':
                    prop_value = child[0].text

            return prop_name, prop_value
        except RuntimeError:
            logger.error('Failed to parse XML string,', exc_info=True)
            logger.info('Terminating execution')
            sys.exit(0)


def parse_ica_log(log_path):
    """ Parser for the generated log file after a lisa run - ica.log

    The method iterates until the start of the test outcome section. After that
     it searches, using regex, for predefined fields and saves them in a
     dict structure.

    :param log_path:
    :return:
    """
    logger.debug(
        'Iterating through %s file until the test results part', log_path
    )
    parsed_ica = dict()
    parsed_ica['vms'] = dict()
    parsed_ica['tests'] = dict()
    with open(log_path, 'r') as log_file:
        for line in log_file:
            if line.strip() == 'Test Results Summary':
                break

        # Get timestamp
        parsed_ica['timestamp'] = re.search('([0-9/]+) ([0-9:]+)',
            log_file.next()).group(0)

        vm_name = ""
        for line in log_file:
            line = line.strip().lower()
            if re.search("^vm:", line) and len(line.split()) == 2:
                vm_name = line.split()[1]
                parsed_ica['vms'][vm_name] = dict()
                # Check if there are any details about the VM
                try:
                    parsed_ica['vms'][vm_name]['TestLocation'] = 'Hyper-V'
                except KeyError:
                    parsed_ica['vms'][vm_name] = dict()
                    parsed_ica['vms'][vm_name]['TestLocation'] = 'Azure'

            elif re.search('^test', line) and \
                    re.search('(success$|failed$|aborted$)', line):
                test = line.split()
                try:
                    parsed_ica['tests'][test[1].lower()] = (vm_name, test[3])
                except KeyError:
                    logging.debug('Test %s was not listed in Test Suites '
                                  'section.It will be ignored from the final'
                                  'results', test)
            elif re.search('^os', line):
                parsed_ica['vms'][vm_name]['hostOS'] = line.split(':')[1].strip()
            elif re.search('^server', line):
                parsed_ica['vms'][vm_name]['hvServer'] = line.split(':')[1].strip()
            elif re.search('^logs can be found at', line):
                parsed_ica['logPath'] = line.split()[-1]
            elif re.search('^lis version', line):
                parsed_ica['lisVersion'] = line.split(':')[1].strip()

    return parsed_ica


def parse_from_csv(csv_path):
    """
    Strip and read csv file into a dict data type.
    :param csv_path: csv file path
    :return: <list of dict> e.g. [{'t_col1': 'val1',
                                   't_col2': 'val2',
                                   ...
                                   },
                                  ...]
             None - on error
    """
    # python [2.7.10, 3.0)  does not support context manager for fileinput
    # strip csv of empty spaces or tabs
    f = fileinput.input(csv_path, inplace=True)
    for line in f:
        # redirect std to file write
        print(' '.join(line.split()))
    f.close()

    list_csv_dict = []
    with open(csv_path, 'rb') as f:
        try:
            csv_dialect = csv.Sniffer().sniff(f.read(), delimiters=";, ")
        except Exception as e:
            logger.error('Error reading csv file {}: {}'.format(csv_path, e))
            return None
        f.seek(0)
        reader = csv.DictReader(f, dialect=csv_dialect)
        for csv_dict in reader:
            list_csv_dict.append(csv_dict)
    return list_csv_dict
