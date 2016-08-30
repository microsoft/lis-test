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
import os
import sys
import csv
import fileinput
import zipfile
import shutil

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


class BaseLogsReader(object):
    """
    Base class for collecting data from multiple log files
    """
    def __init__(self, log_path):
        """
        Init Base logger.
        :param log_path: Required
        """
        if zipfile.is_zipfile(log_path):
            dir_path = os.path.dirname(os.path.abspath(log_path))
            # extracting zip to current path
            # it is required that all logs are zipped in a folder
            with zipfile.ZipFile(log_path, "r") as z:
                unzip_folder = [f for f in z.namelist()
                                if f.endswith('/')][0][:-1]
                z.extractall(dir_path)
            self.log_path = os.path.join(dir_path, unzip_folder)
            self.cleanup = True
        else:
            self.log_path = log_path
            self.cleanup = False
        self.headers = None
        self.log_matcher = None

    @property
    def log_files(self):
        """
        Compute all files from a path.
        :returns: List
        :rtype: List or None
        """
        return [log_name for log_name in os.listdir(self.log_path)
                if os.path.isfile(os.path.join(self.log_path, log_name))]

    def teardown(self):
        """
        Cleanup files/folders created for setting up the parser.
        :return: None
        """
        if self.cleanup:
            shutil.rmtree(self.log_path)

    def collect_data(self, f_match, log_file, log_dict):
        """
        Placeholder method for collecting data. Will be overwritten in
        subclasses with the logic.
        :param f_match: regex file matcher
        :param log_file: log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        return log_dict

    def process_logs(self):
        """
        General data collector method parsing through each log file matching the
        regex filter and call on self.collect_data() for the customized logic.
        :return: <list of dict> e.g. [{'t_col1': 'val1',
                                   't_col2': 'val2',
                                   ...
                                   },
                                  ...]
             [] - on failed parsing
        """
        list_log_dict = []
        for log_file in self.log_files:
            f_match = re.match(self.log_matcher, log_file)
            if not f_match:
                continue
            log_dict = dict.fromkeys(self.headers)
            list_log_dict.append(self.collect_data(f_match, log_file, log_dict))
        self.teardown()
        return list_log_dict


class FIOLogsReader(BaseLogsReader):
    """
    Subclass for parsing FIO log files e.g.
    PERF-8kFIO_Performance_FIO_FIOLog-qXXX.log
    """
    def __init__(self, log_path=None):
        super(FIOLogsReader, self).__init__(log_path)
        self.headers = ['rand-read:', 'rand-read: latency',
                        'rand-write: latency', 'seq-write: latency',
                        'rand-write:', 'seq-write:', 'seq-read:',
                        'seq-read: latency', 'BlockSize']
        self.log_matcher = 'PERF-[0-9]+[a-zA-Z_]+FIOLog-(q[0-9]+)'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for FIO test case.
        :param f_match: regex file matcher
        :param log_file: log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['BlockSize'] = f_match.group(1)
        with open(os.path.join(self.log_path, log_file), 'r') as f:
            lines = f.readlines()
            for key in log_dict:
                if not log_dict[key]:
                    for i in range(0, len(lines)):
                        if all(markers in lines[i] for markers in
                               [key.split(':')[0], 'pid=']):
                            if 'latency' in key:
                                lat = re.match('.+lat \(.+avg=([0-9. ]+)',
                                               lines[i + 4])
                                if lat:
                                    log_dict[key] = lat.group(1).strip()
                            else:
                                iops = re.match('.+iops=([0-9. ]+)',
                                                lines[i + 1])
                                if iops:
                                    log_dict[key] = iops.group(1).strip()
        return log_dict


class NTTTCPLogsReader(BaseLogsReader):
    """
    Subclass for parsing NTTTCP log files e.g.
    ntttcp-pXXX.log
    tcping-ntttcp-pXXX.log - avg latency
    """
    def __init__(self, log_path=None):
        super(NTTTCPLogsReader, self).__init__(log_path)
        self.headers = ['#test_connections', 'throughput_gbps',
                        'average_tcp_latency', 'average_packet_size']
        self.log_matcher = 'ntttcp-p([0-9X]+)'
        self.eth_log_csv = parse_from_csv(os.path.join(self.log_path,
                                                       'eth_report.log'))

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for NTTTCP test case.
        :param f_match: regex file matcher
        :param log_file: log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        # compute the number of connections from the log name
        n_conn = reduce(lambda x, y: int(x) * int(y),
                        f_match.group(1).split('X'))
        log_dict['#test_connections'] = n_conn
        for key in log_dict:
            if not log_dict[key]:
                if 'throughput' in key:
                    with open(os.path.join(self.log_path, log_file), 'r') as f:
                        lines = f.readlines()
                        for i in range(0, len(lines)):
                            throughput = re.match('.+throughput.+:([0-9.]+)',
                                                  lines[i])
                            if throughput:
                                log_dict[key] = throughput.group(1).strip()
                elif 'latency' in key:
                    lat_file = os.path.join(self.log_path,
                                            'lagscope-ntttcp-p{}.log'
                                            .format(f_match.group(1)))
                    with open(lat_file, 'r') as f:
                        lines = f.readlines()
                        for i in range(0, len(lines)):
                            latency = re.match('.+avg = ([0-9.]+)', lines[i])
                            if latency:
                                log_dict[key] = latency.group(1).strip()
                elif 'packet_size' in key:
                    avg_pkg_size = [elem[key] for elem in self.eth_log_csv
                                    if (int(elem[self.headers[0]]) ==
                                        log_dict[self.headers[0]])]
                    try:
                        log_dict[key] = avg_pkg_size[0].strip()
                    except IndexError:
                        logger.warning('Could not find average_packet size in '
                                       'eth_report.log')
                        raise
        return log_dict
