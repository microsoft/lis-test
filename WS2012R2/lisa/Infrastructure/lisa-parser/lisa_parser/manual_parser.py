import argparse
import csv
import os
import sys
import xml.etree.ElementTree as ET
from file_parser import NTTTCPLogsReader
from file_parser import IPERFLogsReader
from file_parser import FIOLogsReaderRaid


def get_parameters():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logs_path",
                        help="--logs_path")
    parser.add_argument("--test_type",
                        help="--test_type")
    parser.add_argument("--output",
                        help="--output")
    params = parser.parse_args()

    if not (os.path.isfile(params.logs_path) or 
            os.path.isdir(params.logs_path)):
        sys.exit("You need to specify an existing path to logs")
    if not params.output:
        sys.exit("You need to specify output path")
    if not params.test_type:
        sys.exit("You need to specify a valid test type")

    return params


def get_suite_data(test_suite):
    tests = []

    for child in test_suite:
        if child.tag == 'testcase':
            test_result = dict()
            test_result['Test_Name'] = child.attrib['name']
            test_result['Test_Time'] = child.attrib['time']
            failed = False
            for prop in child:
                if prop.tag == 'failure':
                    failed = True
            if failed:
                test_result['Test_Result'] = "Fail"
            else:
                test_result['Test_Result'] = "Pass"
            tests.append(test_result)
    return tests


def get_fixed_xml(xml_path):
    fixed_xml = ''
    with open(xml_path, 'r') as file:
        xml_lines = file.readlines()
    for line in xml_lines:
        if '>...<' not in line:
            fixed_xml += line
    tree = ET.fromstring(fixed_xml)
    return tree


def clean_duplicates(test_list):
    for test in test_list:
        nr = test_list.count(test)
        if nr > 1:
            for i in range(1, nr):
                test_list.remove(test)
    return test_list


def parse_xml(xml_path):
    tests = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except ET.ParseError:
        root = get_fixed_xml(xmlPath)

    if root.tag == 'testsuites':
        for test_suite in root:
            tests += get_suite_data(test_suite)
    else:
        tests = get_suite_data(root)

    tests = clean_duplicates(tests)
    return tests


def order_table(log_table, key):
    ordered_table = []

    while log_table:
        min = log_table[0][key]
        min_obj = log_table[0]
        for line in log_table:
            if line[key] < min:
                min = line[key]
                min_obj = line

        ordered_table.append(min_obj)
        log_table.remove(min_obj)
    return ordered_table


def strip_keys(log_table):
    new_logs = []
    for row in log_table:
        new_row = dict()
        for key in row.keys():
            new_row[key.strip(":")] = row[key]
        new_logs.append(new_row)
        
    return new_logs 


def parse_logs(logs_path, test_type):
    if test_type.lower() == 'sr-iov_tcp':
        parsed_logs = NTTTCPLogsReader(logs_path).process_logs()
        ordered_logs = order_table(parsed_logs, 'NumberOfConnections')
    elif test_type.lower() == 'sr-iov_udp':
        parsed_logs = IPERFLogsReader(logs_path).process_logs()
        ordered_logs = order_table(parsed_logs, 'NumberOfConnections')
    elif test_type.lower() == 'fio_raid':
        parsed_logs = FIOLogsReaderRaid(logs_path).process_logs()
        ordered_logs = order_table(parsed_logs, 'QDepth')
        ordered_logs = order_table(ordered_logs, 'BlockSize_KB')
        ordered_logs = strip_keys(ordered_logs)
    elif test_type.lower() == 'functional':
        return parse_xml(logs_path)
    return ordered_logs


def export_csv(output_path, results):
    with open(output_path, 'w') as csvfile:
        keys = results[0].keys()
        writer = csv.DictWriter(csvfile, fieldnames=keys)
        writer.writeheader()
        for row in results:
            writer.writerow(row)


if __name__ == "__main__":
    params = get_parameters()
    parsed_logs = parse_logs(params.logs_path, params.test_type)
    export_csv(params.output, parsed_logs)
