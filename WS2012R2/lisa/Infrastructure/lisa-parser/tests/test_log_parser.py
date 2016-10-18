from unittest import TestCase
from create_files import create_ica_file
from os import remove, path
from nose.tools import assert_dict_equal
from lisa_parser.file_parser import parse_ica_log


class TestParseIca(TestCase):
    def setUp(self):
        self.file_path = path.join(path.dirname(__file__), 'test.log')
        create_ica_file(self.file_path)
        self.maxDiff = None

    def tearDown(self):
        remove(self.file_path)

    def test_normal_run(self):
        assert_dict_equal(
            parse_ica_log(self.file_path),
            {
                'timestamp': '01/01/2016 21:21:21',
                'tests': {
                    'internalnetwork': ('vmname', 'failed'),
                    'external': ('vmname', 'success')
                },
                'logPath': 'path_to_logs',
                'vms': {
                    'vmname': {
                        'hostOS': 'microsoft windows server 2012',
                        'TestLocation': 'Hyper-V',
                        'hvServer': 'localhost'
                    }
                },
                'lisVersion': '4.4.21-64-default'
                }
        )
