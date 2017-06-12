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
import csv
import logging
from collections import defaultdict
from os import listdir, mkdir, rename
from os.path import join, isfile, exists

import json


logger = logging.getLogger(__name__)


class MonitorRuns(object):
    def __init__(self, summary_log_path):
        self.summary_path = summary_log_path
        self.tests_report = defaultdict(dict)
        self.test_coverage = defaultdict(self.get_report_dict)
    
    @staticmethod
    def get_report_dict():
        return {
            'total': 0,
            'passed': 0,
            'skipped': 0,
            'aborted': 0,
            'failed': 0
        }

    @staticmethod
    def get_test_summary(tests_list):
        tests = {
            'summary': {
                'total': len(tests_list),
                'passed': 0,
                'skipped': 0,
                'aborted': 0,
                'failed': 0
            },
            'issues': {}
        }
        for test in tests_list:
        	tests['summary'][test['TestResult']] += 1
        	if test['TestResult'] == 'aborted' or test['TestResult'] == 'failed':
        		tests['issues'][test['TestCaseName']] = test['TestResult']
        return tests
    
    def __call__(self):
        # TODO: Find better way to save distro_name
        backup_folder = join(self.summary_path, 'previous_reports')
        result_folder = join(self.summary_path, str(datetime.date.today()))
        if not exists(backup_folder): mkdir(backup_folder)
        if not exists(backup_folder): mkdir(result_folder)
        for json_file in listdir(self.summary_path):
            distro_name = json_file.partition('-')[0]
            file_path = join(self.summary_path, json_file)
            if isfile(file_path):
                self.parse_json_report(distro_name, file_path)
                rename(file_path, join(backup_folder, json_file))
        self.write_json(join(result_folder, 'coverage.json'), self.test_coverage)
        self.write_csv(self.test_coverage.keys(), self.tests_report, result_folder)
    
    @staticmethod
    def write_json(file_path, dict_value):
        with open(file_path, 'w') as summary_file:
            json.dump(
                dict_value,
                summary_file,
                indent=4,
                sort_keys=True
            )
        
    def parse_json_report(self, distro_name, file_path):
        with open(file_path, 'r') as report_content:
            test_dict = json.load(report_content)
            for result, count in test_dict['summary'].items():
                self.test_coverage[distro_name][result] += count
            for test_name, result in test_dict['issues'].items():
                self.tests_report[test_name][distro_name] = result
    
    @staticmethod
    def write_csv(distro_names, test_results, folder_path, file_name='test_report.csv'):
        with open(join(folder_path, file_name), 'w') as csv_file:
            summary_writer = csv.writer(csv_file, delimiter=',')
            summary_writer.writerow(['TestName'] + distro_names)
            for test_name, report in test_results.items():
                distro_results = [report.get(distro, 'passed') for distro in distro_names]
                summary_writer.writerow([test_name] + distro_results)
