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
import time
import zipfile
import shutil

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class BaseLogsReader(object):
    """
    Base class for collecting data from multiple log files
    """
    CUNIT = {'us': 10**-3,
             'ms': 1,
             's': 10**3}

    def __init__(self, log_path):
        """
        Init Base logger.
        :param log_path: Path containing zipped logs.
        """
        self.cleanup = False
        self.log_path = self.process_log_path(log_path)
        self.headers = None
        self.log_matcher = None
        self.log_base_path = log_path
        self.sorter = []

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
                zip_content = z.namelist()
                if any('/' in fis for fis in zip_content):
                    unzip_folder = next(fol for fol in zip_content if '/' in fol).split('/')[0]
                else:
                    unzip_folder = ''
                z.extractall(dir_path)
            if unzip_folder:
                print(unzip_folder)
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

    def get_summary_log(self):
        summary_log = [log_file for log_file in os.listdir(os.path.dirname(self.log_base_path))
                       if 'summary.log' in log_file][0]
        summary_path = os.path.join(os.path.dirname(self.log_base_path), summary_log)
        log_dict = {}
        with open(summary_path, 'r') as f:
            for line in f:
                if not log_dict.get('date', None):
                    date = re.match('[A-Za-z]{3}\s*([A-Za-z]{3})\s*([0-9]{2})\s*'
                                    '[0-9]{2}:[0-9]{2}:[0-9]{2}\s*([0-9]{4})', line)
                    if date:
                        month = time.strptime(date.group(1), '%b').tm_mon
                        log_dict['date'] = date.group(3) + '-' + str(month) + '-' + date.group(2)
                if not log_dict.get('kernel', None):
                    kernel = re.match('.+:\s*Kernel\s*Version\s*:\s*([a-z0-9-.]+)', line)
                    if kernel:
                        log_dict['kernel'] = kernel.group(1).strip()
                if not log_dict.get('guest_os', None):
                    guest_os = re.match('.+:\s*Guest\s*OS\s*:\s*([a-zA-Z0-9. ]+)', line)
                    if guest_os:
                        log_dict['guest_os'] = guest_os.group(1).strip()
        return log_dict

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
            collected_data = self.collect_data(f_match, log_file, log_dict)
            list_log_dict.append(collected_data)

        self.teardown()
        if self.sorter:
            def cast_int_column(col):
                ret_tuple = ()
                for i in self.sorter:
                    if type(col[i]) is str and col[i].isdigit():
                        ret_tuple += (int(col[i]),)
                    else:
                        ret_tuple += (col[i],)
                return ret_tuple
            list_log_dict = sorted(list_log_dict, key=cast_int_column)
        return list_log_dict


class OrionLogsReader(BaseLogsReader):
    """
    Subclass for parsing Orion log files e.g.
    rndrd_4K_1_sysbench.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None,
                 disk_setup=None):
        super(OrionLogsReader, self).__init__(log_path)
        self.headers = ['TestCaseName', 'HostType', 'InstanceSize', 'DiskSetup', 'FileTestMode',
                        'BlockSize_Kb', 'Threads', 'Latency95Percentile_ms',
                        'RequestsExecutedPerSec']
        self.sorter = ['FileTestMode', 'BlockSize_Kb', 'Threads']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.disk_setup = disk_setup

        self.log_matcher = '([a-z]+)_([0-9]+)K_([0-9]+)_sysbench.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for FIO test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['DiskSetup'] = self.disk_setup
        log_dict['TestMode'] = 'fileio'
        log_dict['FileTestMode'] = f_match.group(1)
        log_dict['BlockSize_Kb'] = f_match.group(2)
        log_dict['Threads'] = f_match.group(3)

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'rU') as fl:
            for key in log_dict:
                if not log_dict[key]:
                    for line in fl:
                        if 'Latency' in key:
                            lat = re.match('\s*approx.\s*95\s*percentile:\s*([0-9.]+)([a-z]+)',
                                           line)
                            if lat:
                                unit = lat.group(2).strip()
                                log_dict[key] = float(
                                    lat.group(1).strip()) * self.CUNIT[unit]
                        elif 'Requests' in key:
                            req = re.match('\s*([0-9.]+)\s*Requests/sec\s*executed', line)
                            if req:
                                log_dict[key] = req.group(1).strip()
        return log_dict


class SysbenchLogsReader(BaseLogsReader):
    """
    Subclass for parsing Sysbench log files e.g.
    rndrd_4K_1_sysbench.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None,
                 disk_setup=None):
        super(SysbenchLogsReader, self).__init__(log_path)
        self.headers = ['TestCaseName', 'HostType', 'InstanceSize', 'DiskSetup', 'FileTestMode',
                        'BlockSize_Kb', 'Threads', 'Latency95Percentile_ms',
                        'RequestsExecutedPerSec']
        self.sorter = ['FileTestMode', 'BlockSize_Kb', 'Threads']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.disk_setup = disk_setup

        self.log_matcher = '([a-z]+)_([0-9]+)K_([0-9]+)_sysbench.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for Sysbench test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['DiskSetup'] = self.disk_setup
        log_dict['TestMode'] = 'fileio'
        log_dict['FileTestMode'] = f_match.group(1)
        log_dict['BlockSize_Kb'] = f_match.group(2)
        log_dict['Threads'] = f_match.group(3)

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'rU') as fl:
            for key in log_dict:
                if not log_dict[key]:
                    for line in fl:
                        if 'Latency' in key:
                            lat = re.match('\s*approx.\s*95\s*percentile:\s*([0-9.]+)([a-z]+)',
                                           line)
                            if lat:
                                unit = lat.group(2).strip()
                                log_dict[key] = float(
                                    lat.group(1).strip()) * self.CUNIT[unit]
                        elif 'Requests' in key:
                            req = re.match('\s*([0-9.]+)\s*Requests/sec\s*executed', line)
                            if req:
                                log_dict[key] = req.group(1).strip()
        return log_dict


class MemcachedLogsReader(BaseLogsReader):
    """
    Subclass for parsing Memcached log files e.g.
    1.memtier_benchmark.run.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None):
        super(MemcachedLogsReader, self).__init__(log_path)
        self.headers = ['TestConnections', 'Threads', 'ConnectionsPerThread',
                        'RequestsPerThread', 'BestLatency_ms', 'WorstLatency_ms',
                        'AverageLatency_ms', 'BestOpsPerSec',
                        'WorstOpsPerSec', 'AverageOpsPerSec']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.log_matcher = '([0-9]+).memtier_benchmark.run.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for Memcached test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['TestConnections'] = f_match.group(1)

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'r') as fl:
            f_lines = fl.readlines()
            for x in range(0, len(f_lines)):
                for key in log_dict:
                    if not log_dict[key]:
                        threads = re.match('\s*([0-9]+)\s*Threads', f_lines[x])
                        if threads:
                            log_dict['Threads'] = threads.group(1)
                        conn_per_thread = re.match('\s*([0-9]+)\s*Connections\s*per\s*thread',
                                                   f_lines[x])
                        if conn_per_thread:
                            log_dict['ConnectionsPerThread'] = conn_per_thread.group(1)
                        req_per_thread = re.match('\s*([0-9]+)\s*Requests\s*per\s*thread',
                                                  f_lines[x])
                        if req_per_thread:
                            log_dict['RequestsPerThread'] = req_per_thread.group(1)
                        best_table = re.match('\s*BEST\s*RUN\s*RESULTS\s*', f_lines[x])
                        if best_table:
                            best_totals = re.match('\s*Totals\s*([0-9.]+)\s*'
                                                   '([0-9.]+)\s*([0-9.]+)\s*'
                                                   '([0-9.]+)\s*([0-9.]+)',
                                                   f_lines[x + 7])
                            log_dict['BestOpsPerSec'] = best_totals.group(1)
                            log_dict['BestLatency_ms'] = best_totals.group(4)
                        worst_table = re.match('\s*WORST\s*RUN\s*RESULTS\s*', f_lines[x])
                        if worst_table:
                            worst_totals = re.match('\s*Totals\s*([0-9.]+)\s*'
                                                    '([0-9.]+)\s*([0-9.]+)\s*'
                                                    '([0-9.]+)\s*([0-9.]+)', f_lines[x + 7])
                            log_dict['WorstOpsPerSec'] = worst_totals.group(1)
                            log_dict['WorstLatency_ms'] = worst_totals.group(4)
                        average_table = re.match('\s*AGGREGATED\s*AVERAGE\s*RESULTS\s*',
                                                 f_lines[x])
                        if average_table:
                            average_totals = re.match('\s*Totals\s*([0-9.]+)\s*'
                                                      '([0-9.]+)\s*([0-9.]+)\s*'
                                                      '([0-9.]+)\s*([0-9.]+)', f_lines[x + 7])
                            log_dict['AverageOpsPerSec'] = average_totals.group(1)
                            log_dict['AverageLatency_ms'] = average_totals.group(4)
        return log_dict


class RedisLogsReader(BaseLogsReader):
    """
    Subclass for parsing Redis log files e.g.
    1.redis.set.get.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None):
        super(RedisLogsReader, self).__init__(log_path)
        self.headers = ['TestPipelines', 'TotalRequests', 'ParallelClients', 'Payload_bytes',
                        'SETRRequestsPerSec', 'GETRequestsPerSec']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.log_matcher = '([0-9]+).redis.set.get.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for Redis test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['TestPipelines'] = f_match.group(1)

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'r') as fl:
            f_lines = fl.readlines()
            for x in range(0, len(f_lines)):
                op_header = re.match('.+\s*([A-Z]{3})\s*.+', f_lines[x])
                if op_header:
                    op_type = op_header.group(1)
                    for j in range(x, len(f_lines)):
                        total_requests = re.match('\s*([0-9]+)\s*requests\s*completed\s*in',
                                                  f_lines[j])
                        if total_requests:
                            if not log_dict.get('TotalRequests', None):
                                log_dict['TotalRequests'] = total_requests.group(1)
                        parallel_clients = re.match('\s*([0-9]+)\s*parallel\s*clients', f_lines[j])
                        if parallel_clients:
                            if not log_dict.get('ParallelClients', None):
                                log_dict['ParallelClients'] = parallel_clients.group(1)
                        payload = re.match('\s*([0-9]+)\s*bytes\s*payload', f_lines[j])
                        if payload:
                            if not log_dict.get('Payload_bytes', None):
                                log_dict['Payload_bytes'] = payload.group(1)
                        requests = re.match('\s*([0-9.]+)\s*requests\s*per\s*second', f_lines[j])
                        if requests:
                            if not log_dict.get(op_type + 'RequestsPerSec', None):
                                log_dict[op_type + 'RequestsPerSec'] = requests.group(1)
        return log_dict


class ApacheLogsReader(BaseLogsReader):
    """
    Subclass for parsing Apache bench log files e.g.
    1.apache.bench.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None):
        super(ApacheLogsReader, self).__init__(log_path)
        self.headers = ['TestConcurrency', 'NumberOfAbInstances', 'ConcurrencyPerAbInstance',
                        'WebServerVersion', 'Document_bytes', 'CompleteRequests',
                        'RequestsPerSec', 'TransferRate_KBps', 'MeanConnectionTimes_ms']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.log_matcher = '([0-9]+).apache.bench.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for Apache Bench test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['TestConcurrency'] = f_match.group(1)
        log_dict['NumberOfAbInstances'] = 0
        log_dict['ConcurrencyPerAbInstance'] = 0
        log_dict['CompleteRequests'] = 0
        log_dict['RequestsPerSec'] = 0
        log_dict['TransferRate_KBps'] = 0
        log_dict['MeanConnectionTimes_ms'] = 0

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'r') as fl:
            for line in fl:
                web_server_version = re.match('\s*Server\s*Software:\s*([a-zA-Z0-9./]+)', line)
                if web_server_version:
                    if not log_dict.get('WebServerVersion', None):
                        log_dict['WebServerVersion'] = web_server_version.group(1)
                doc_len = re.match('\s*Document\s*Length:\s*([0-9]+)\s*bytes\s*', line)
                if doc_len:
                    if not log_dict.get('Document_bytes', None):
                        log_dict['Document_bytes'] = doc_len.group(1)
                concurrency = re.match('\s*Concurrency\s*Level:\s*([0-9]+)', line)
                if concurrency:
                    if not log_dict.get('ConcurrencyPerAbInstance', None):
                        log_dict['ConcurrencyPerAbInstance'] = concurrency.group(1)

                requests = re.match('\s*Complete\s*requests:\s*([0-9]+)', line)
                if requests:
                    log_dict['CompleteRequests'] += int(requests.group(1))
                    log_dict['NumberOfAbInstances'] += 1
                req_sec = re.match('\s*Requests\s*per\s*second:\s*([0-9.]+)\s*', line)
                if req_sec:
                    r = round(log_dict['RequestsPerSec'] + float(req_sec.group(1)), 3)
                    log_dict['RequestsPerSec'] = r
                transfer = re.match('\s*Transfer\s*rate:\s*([0-9.]+)\s*', line)
                if transfer:
                    t = round(log_dict['TransferRate_KBps'] + float(transfer.group(1)), 3)
                    log_dict['TransferRate_KBps'] = t
                lat = re.match('\s*Total:\s*([0-9.]+)\s*([0-9.]+)\s*([0-9.]+)'
                               '\s*([0-9.]+)\s*([0-9.]+)*', line)
                if lat:
                    if log_dict.get('MeanConnectionTimes_ms', None) == 0:
                        log_dict['MeanConnectionTimes_ms'] = float(lat.group(2))
                    else:
                        mean = round((log_dict['MeanConnectionTimes_ms'] + float(
                                lat.group(2))) / 2, 3)
                        log_dict['MeanConnectionTimes_ms'] = mean
        return log_dict


class MariadbLogsReader(BaseLogsReader):
    """
    Subclass for parsing MariaDB log files e.g.
    1.sysbench.mariadb.run.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None,
                 instance_size=None, disk_setup=None):
        super(MariadbLogsReader, self).__init__(log_path)
        self.headers = ['TestMode', 'Driver', 'Threads', 'TotalQueries',
                        'TransactionsPerSec', 'DeadlocksPerSec',
                        'RWRequestsPerSec', 'Latency95Percentile_ms']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.disk_setup = disk_setup
        self.log_matcher = '([0-9]+).sysbench.mariadb.run.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for MariaDB test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['DiskSetup'] = self.disk_setup
        log_dict['Threads'] = f_match.group(1)

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'r') as fl:
            for line in fl:
                test_mode = re.match('\s*Doing\s*([A-Z]+)\s*test\.', line)
                if test_mode and not log_dict.get('TestMode', None):
                    log_dict['TestMode'] = test_mode.group(1)
                driver = re.match('\s*No\s*DB\s*drivers\s*specified,\s*using\s*([a-z]+)', line)
                if driver and not log_dict.get('Driver', None):
                    log_dict['Driver'] = driver.group(1)
                total_q = re.match('\s*total:\s*([0-9]+)\s*', line)
                if total_q and not log_dict.get('Total_queries', None):
                    log_dict['TotalQueries'] = total_q.group(1)
                trans = re.match('\s*transactions:\s*([0-9]+)\s*\(([0-9.]+)\s*per\s*sec\.\)', line)
                if trans and not log_dict.get('Transactions_per_sec', None):
                    log_dict['TransactionsPerSec'] = trans.group(2)
                dead = re.match('\s*deadlocks:\s*([0-9]+)\s*\(([0-9.]+)\s*per\s*sec\.\)',
                                line)
                if dead and not log_dict.get('Deadlocks_per_sec', None):
                    log_dict['DeadlocksPerSec'] = dead.group(2)
                rw = re.match('\s*read/write\s*requests:\s*([0-9]+)\s*\(([0-9.]+)\s*per\s*sec\.\)',
                              line)
                if rw and not log_dict.get('RW_requests_per_sec', None):
                    log_dict['RWRequestsPerSec'] = rw.group(2)
                lat = re.match('\s*approx\.\s*95\s*percentile:\s*([0-9.]+)\s*ms', line)
                if lat and not log_dict.get('Latency_95_percentile_ms', None):
                    log_dict['Latency95Percentile_ms'] = lat.group(1)
        return log_dict


class MongodbLogsReader(BaseLogsReader):
    """
    Subclass for parsing MongoDB log files e.g.
    1.ycsb.run.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None,
                 disk_setup=None):
        super(MongodbLogsReader, self).__init__(log_path)
        self.headers = ['Threads', 'TotalOpsPerSec',
                        'ReadOps', 'ReadLatency95Percentile_us',
                        'CleanupOps', 'CleanupLatency95Percentile_us',
                        'UpdateOps', 'UpdateLatency95Percentile_us',
                        'ReadFailedOps',
                        'ReadFailedLatency95Percentile_us']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.disk_setup = disk_setup
        self.log_matcher = '([0-9]+).ycsb.run.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for FIO test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['DiskSetup'] = self.disk_setup
        log_dict['Threads'] = f_match.group(1)

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'r') as fl:
            for line in fl:
                throughput = re.match('\s*\[OVERALL\],\s*Throughput\(ops/sec\),\s*([0-9.]+)', line)
                if throughput and not log_dict.get('TotalOpsPerSec', None):
                    log_dict['TotalOpsPerSec'] = round(float(throughput.group(1)), 3)
                read_ops = re.match('\s*\[READ\],\s*Operations,\s*([0-9.]+)', line)
                if read_ops and not log_dict.get('ReadOps', None):
                    log_dict['ReadOps'] = read_ops.group(1)
                read_lat = re.match('\s*\[READ\],\s*95thPercentileLatency\(us\),\s*([0-9.]+)',
                                    line)
                if read_lat and not log_dict.get('ReadLatency95Percentile_us', None):
                    log_dict['ReadLatency95Percentile_us'] = read_lat.group(1)
                clean_ops = re.match('\s*\[CLEANUP\],\s*Operations,\s*([0-9.]+)', line)
                if clean_ops and not log_dict.get('CleanupOps', None):
                    log_dict['CleanupOps'] = clean_ops.group(1)
                clean_lat = re.match('\s*\[CLEANUP\],\s*95thPercentileLatency\(us\),\s*([0-9.]+)',
                                     line)
                if clean_lat and not log_dict.get('CleanupLatency95Percentile_us', None):
                    log_dict['CleanupLatency95Percentile_us'] = clean_lat.group(1)
                update_ops = re.match('\s*\[UPDATE\],\s*Operations,\s*([0-9.]+)', line)
                if update_ops and not log_dict.get('UpdateOps', None):
                    log_dict['UpdateOps'] = update_ops.group(1)
                update_lat = re.match('\s*\[UPDATE\],\s*95thPercentileLatency\(us\),\s*([0-9.]+)',
                                      line)
                if update_lat and not log_dict.get('UpdateLatency95Percentile_us', None):
                    log_dict['UpdateLatency95Percentile_us'] = update_lat.group(1)
                read_fail_ops = re.match('\s*\[READ-FAILED\],\s*Operations,\s*([0-9.]+)',
                                         line)
                if read_fail_ops and not log_dict.get('ReadFailedOps', None):
                    log_dict['ReadFailedOps'] = read_fail_ops.group(1)
                read_fail_lat = re.match('\s*\[READ-FAILED\],\s*95thPercentile'
                                         'Latency\(us\),\s*([0-9.]+)', line)
                if read_fail_lat and not log_dict.get('ReadFailedLatency95Percentile_us', None):
                    log_dict['ReadFailedLatency95Percentile_us'] = read_fail_lat.group(1)
        return log_dict


class ZookeeperLogsReader(BaseLogsReader):
    """
    Subclass for parsing Zookeeper log files e.g.
    1.zookeeper.latency.log
    """
    def __init__(self, log_path=None, test_case_name=None, host_type=None, instance_size=None,
                 cluster_setup=None):
        super(ZookeeperLogsReader, self).__init__(log_path)
        self.headers = ['Threads', 'TotalCreatedCallsPerSec',
                        'TotalGetCallsPerSec', 'TotalSetCallsPerSec',
                        'TotalDeletedCallsPerSec', 'TotalWatchedCallsPerSec']
        self.test_case_name = test_case_name
        self.host_type = host_type
        self.instance_size = instance_size
        self.cluster_setup = cluster_setup
        self.log_matcher = '([0-9]+).zookeeper.latency.log'

    def collect_data(self, f_match, log_file, log_dict):
        """
        Customized data collect for Zookeeper test case.
        :param f_match: regex file matcher
        :param log_file: full path log file name
        :param log_dict: dict constructed from the defined headers
        :return: <dict> {'head1': 'val1', ...}
        """
        log_dict['TestCaseName'] = self.test_case_name
        log_dict['HostType'] = self.host_type
        log_dict['InstanceSize'] = self.instance_size
        log_dict['ClusterSetup'] = self.cluster_setup
        log_dict['Threads'] = f_match.group(1)
        log_dict['NodeSize_bytes'] = 100
        log_dict['TotalCreatedCallsPerSec'] = 0
        log_dict['TotalSetCallsPerSec'] = 0
        log_dict['TotalGetCallsPerSec'] = 0
        log_dict['TotalDeletedCallsPerSec'] = 0
        log_dict['TotalWatchedCallsPerSec'] = 0

        summary = self.get_summary_log()
        log_dict['KernelVersion'] = summary['kernel']
        log_dict['TestDate'] = summary['date']
        log_dict['GuestOS'] = summary['guest_os']

        with open(log_file, 'r') as fl:
            for line in fl:
                created = re.match('\s*created\s*([0-9]+)\s*permanent\s*znodes\s*in\s*([0-9]+)'
                                   '\s*ms\s*\(([0-9.]+)\s*ms/op\s*([0-9.]+)/sec\)', line)
                if created:
                    r = round(log_dict['TotalCreatedCallsPerSec'] + float(created.group(4)), 3)
                    log_dict['TotalCreatedCallsPerSec'] = r
                set_ops = re.match('\s*set\s*([0-9]+)\s*znodes\s*in\s*([0-9]+)\s*ms\s*\(([0-9.]+)'
                                   '\s*ms/op\s*([0-9.]+)/sec\)', line)
                if set_ops:
                    r = round(log_dict['TotalSetCallsPerSec'] + float(set_ops.group(4)), 3)
                    log_dict['TotalSetCallsPerSec'] = r
                get_ops = re.match('\s*get\s*([0-9]+)\s*znodes\s*in\s*([0-9]+)\s*ms\s*\(([0-9.]+)'
                                   '\s*ms/op\s*([0-9.]+)/sec\)', line)
                if get_ops:
                    r = round(log_dict['TotalGetCallsPerSec'] + float(get_ops.group(4)), 3)
                    log_dict['TotalGetCallsPerSec'] = r
                deleted = re.match('\s*deleted\s*([0-9]+)\s*permanent\s*znodes\s*in\s*([0-9]+)'
                                   '\s*ms\s*\(([0-9.]+)\s*ms/op\s*([0-9.]+)/sec\)', line)
                if deleted:
                    r = round(log_dict['TotalDeletedCallsPerSec'] + float(deleted.group(4)), 3)
                    log_dict['TotalDeletedCallsPerSec'] = r
                watched = re.match('\s*watched\s*([0-9]+)\s*znodes\s*in\s*([0-9]+)\s*ms'
                                   '\s*\(([0-9.]+)\s*ms/op\s*([0-9.]+)/sec\)', line)
                if watched:
                    r = round(log_dict['TotalWatchedCallsPerSec'] + float(watched.group(4)), 3)
                    log_dict['TotalWatchedCallsPerSec'] = r
        return log_dict
