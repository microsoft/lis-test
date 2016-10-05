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
            logger.debug('Parsing line %s', line)
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
                parsed_ica['vms'][vm_name]['hostOS'] = line.split(':')[1]\
                    .strip()
            elif re.search('^server', line):
                parsed_ica['vms'][vm_name]['hvServer'] = line.split(':')[1]\
                    .strip()
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
    f_csv = fileinput.input(csv_path, inplace=True)
    for line in f_csv:
        # redirect std to file write
        print(' '.join(line.split()))
    f_csv.close()

    list_csv_dict = []
    with open(csv_path, 'rb') as fl:
        try:
            csv_dialect = csv.Sniffer().sniff(fl.read(), delimiters=";, ")
        except Exception as e:
            logger.error('Error reading csv file {}: {}'.format(csv_path, e))
            return None
        fl.seek(0)
        reader = csv.DictReader(fl, dialect=csv_dialect)
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
        :param log_path: Path containing zipped logs.
        """
        self.cleanup = False
        self.log_path = self.process_log_path(log_path)
        self.headers = None
        self.log_matcher = None

    def process_log_path(self, log_path):
        """
        Detect if log_path is a zip, then unzip it and return log's location.
        :param log_path:
        :return: log location - if the log_path is not a zip
                 unzipped location - if log_path is a zip
                 list of zipped logs - if log_path contains the zipped logs
        """
        if zipfile.is_zipfile(log_path):
            dir_path = os.path.dirname(os.path.abspath(log_path))
            # extracting zip to current path
            # it is required that all logs are zipped in a folder
            with zipfile.ZipFile(log_path, 'r') as z:
                if any('/' in fis for fis in z.namelist()):
                    unzip_folder = z.namelist()[0].split('/')[0]
                else:
                    unzip_folder = ''
                z.extractall(dir_path)
            if unzip_folder:
                self.cleanup = True
            return os.path.join(dir_path, unzip_folder)
        elif any(zipfile.is_zipfile(os.path.join(log_path, z))
                 for z in os.listdir(log_path)):
            zip_list = []
            for z in os.listdir(log_path):
                zip_file_path = os.path.join(log_path, z)
                if zipfile.is_zipfile(zip_file_path):
                    zip_list.append(self.process_log_path(zip_file_path))
            return zip_list
        else:
            return log_path

    def teardown(self):
        """
        Cleanup files/folders created for setting up the parser.
        :return: None
        """
        if self.cleanup:
            if isinstance(self.log_path, list):
                for path in self.log_path:
                    shutil.rmtree(path)
            else:
                shutil.rmtree(self.log_path)

    @staticmethod
    def get_log_files(log_path):
        """
        Compute and check all files from a path.
        :param: log_path: path to check
        :returns: List of checked files
        :rtype: List or None
        """
        return [os.path.join(log_path, log_name)
                for log_name in os.listdir(log_path)
                if os.path.isfile(os.path.join(log_path, log_name))]

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
        log_files = []
        if isinstance(self.log_path, list):
            for path in self.log_path:
                log_files.extend(self.get_log_files(path))
        else:
            log_files.extend(self.get_log_files(self.log_path))
        for log_file in log_files:
            f_match = re.match(self.log_matcher, os.path.basename(log_file))
            if not f_match:
                continue
            log_dict = dict.fromkeys(self.headers, '')
            list_log_dict.append(self.collect_data(f_match, log_file, log_dict))
        self.teardown()
        return list_log_dict


class FIOLogsReader(BaseLogsReader):
    """
    Subclass for parsing FIO log files e.g.
    FIOLog-XXXq.log
    """
    # conversion unit dict reference for latency to 'usec'
    CUNIT = {'usec': 1,
             'msec': 1000,
             'sec': 1000000}
    CSIZE = {'K': 1,
             'M': 1024,
             'G': 1048576}

    def __init__(self, log_path=None):
        super(FIOLogsReader, self).__init__(log_path)
        self.headers = ['rand-read:', 'rand-read: latency',
                        'rand-write: latency', 'seq-write: latency',
                        'rand-write:', 'seq-write:', 'seq-read:',
                        'seq-read: latency', 'QDepth', 'BlockSize_KB']
        self.log_matcher = 'FIOLog-([0-9]+)q'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for FIO test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['QDepth'] = int(f_match.group(1))
        with open(log_file, 'r') as fl:
            f_lines = fl.readlines()
            for key in log_dict:
                if not log_dict[key]:
                    if 'BlockSize' in key:
                        block_size = re.match(
                            '.+rw=read, bs=\s*([0-9])([A-Z])-', f_lines[0])
                        um = block_size.group(2).strip()
                        log_dict[key] = \
                            int(block_size.group(1).strip()) * self.CSIZE[um]
                    for x in range(0, len(f_lines)):
                        if all(markers in f_lines[x] for markers in
                               [key.split(':')[0], 'pid=']):
                            if 'latency' in key:
                                lat = re.match(
                                    '\s*lat\s*\(([a-z]+)\).+avg=\s*([0-9.]+)',
                                    f_lines[x + 4])
                                if lat:
                                    unit = lat.group(1).strip()
                                    log_dict[key] = float(
                                        lat.group(2).strip()) * self.CUNIT[unit]
                                else:
                                    log_dict[key] = 0
                            else:
                                iops = re.match('.+iops=\s*([0-9. ]+)',
                                                f_lines[x + 1])
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
                        'average_tcp_latency', 'average_packet_size',
                        'IPVersion', 'Protocol']
        self.log_matcher = 'ntttcp-p([0-9X]+)'
        self.eth_log_csv = dict()
        self.__get_eth_log_csv()

    def __get_eth_log_csv(self):
        if isinstance(self.log_path, list):
            for path in self.log_path:
                self.eth_log_csv[path] = parse_from_csv(os.path.join(
                    path, 'eth_report.log'))
        else:
            self.eth_log_csv[self.log_path] = parse_from_csv(os.path.join(
                self.log_path, 'eth_report.log'))

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for NTTTCP test case.
        :param f_match: regex file matcher
        :param log_file: log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        # compute the number of connections from the log name
        n_conn = reduce(lambda x1, x2: int(x1) * int(x2),
                        f_match.group(1).split('X'))
        log_dict['#test_connections'] = n_conn
        for key in log_dict:
            if not log_dict[key]:
                if 'throughput' in key:
                    log_dict[key] = 0
                    with open(log_file, 'r') as fl:
                        f_lines = fl.readlines()
                        for x in range(0, len(f_lines)):
                            throughput = re.match('.+throughput.+:([0-9.]+)',
                                                  f_lines[x])
                            if throughput:
                                log_dict[key] = throughput.group(1).strip()
                                break
                elif 'latency' in key:
                    log_dict[key] = 0
                    lat_file = os.path.join(os.path.dirname(os.path.abspath(
                        log_file)), 'lagscope-ntttcp-p{}.log'
                        .format(f_match.group(1)))
                    with open(lat_file, 'r') as fl:
                        f_lines = fl.readlines()
                        for x in range(0, len(f_lines)):
                            if not log_dict.get('IPVersion', None):
                                ip_version = re.match('domain:.+(IPv[4,6])',
                                                      f_lines[x])
                                if ip_version:
                                    log_dict['IPVersion'] = ip_version.group(
                                        1).strip()
                            if not log_dict.get('Protocol', None):
                                ip_proto = re.match('protocol:.+([A-Z]{3})',
                                                    f_lines[x])
                                if ip_proto:
                                    log_dict['Protocol'] = ip_proto.group(
                                        1).strip()
                            latency = re.match('.+Average = ([0-9.]+)',
                                               f_lines[x])
                            if latency:
                                log_dict[key] = latency.group(1).strip()
                elif 'packet_size' in key:
                    avg_pkg_size = [elem[key]
                                    for elem in self.eth_log_csv[
                                        os.path.dirname(os.path.abspath(
                                            log_file))]
                                    if (int(elem[self.headers[0]]) ==
                                        log_dict[self.headers[0]])]
                    try:
                        log_dict[key] = avg_pkg_size[0].strip()
                    except IndexError:
                        logger.warning('Could not find average_packet size in '
                                       'eth_report.log')
                        log_dict[key] = 0
        return log_dict
