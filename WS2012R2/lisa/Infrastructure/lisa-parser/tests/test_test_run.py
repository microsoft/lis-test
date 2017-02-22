from unittest import TestCase
from os import remove, path
import create_files
from nose.tools import assert_equal
from lisa_parser.test_run import TestRun


class TestTestRun(TestCase):
    def setUp(self):
        self.test_run = TestRun(skip_vm_check=True, checkpoint_name=False)
        self.xml_file = path.join(path.dirname(__file__), 'test.xml')
        self.log_file = path.join(path.dirname(__file__), 'test.log')
        create_files.create_xml_file(self.xml_file)
        create_files.create_ica_file(self.log_file)

    def tearDown(self):
        remove(self.xml_file)
        remove(self.log_file)

    def test_update_from_xml(self):
        self.test_run.update_from_xml(self.xml_file)
        assert_equal(self.test_run.suite, 'Network')
        assert_equal(self.test_run.vms['vmname'].vm_name, 'vmname')
        assert_equal(self.test_run.vms['vmname'].os, 'linux')
        assert_equal(self.test_run.vms['vmname'].hv_server, 'localhost')

        assert_equal(self.test_run.test_cases['external'].name, 'external')
        assert_equal(self.test_run.test_cases['external'].covered_cases, 'NET-02')

    def test_update_from_ica(self):
        self.test_run.update_from_xml(self.xml_file)
        self.test_run.update_from_ica(self.log_file)
        assert_equal(self.test_run.timestamp, '01/01/2016 21:21:21')
        assert_equal(self.test_run.log_path, 'path_to_logs')
        assert_equal(self.test_run.lis_version, '4.4.21-64-default')
        assert_equal(self.test_run.test_cases['external'].results['vmname'], 'success')
        assert_equal(self.test_run.vms['vmname'].host_os, 'microsoft windows server 2012')
        assert_equal(self.test_run.vms['vmname'].hv_server, 'localhost')
        assert_equal(self.test_run.vms['vmname'].location, 'Hyper-V')

    def test_update_parse_for_insertion(self):
        self.test_run.update_from_xml(self.xml_file)
        self.test_run.update_from_ica(self.log_file)
        insertion_list = self.test_run.parse_for_db_insertion()
        assert_equal(insertion_list[0]['LogPath'], 'path_to_logs')
        assert_equal(insertion_list[0]['TestID'], 'NET-02')
        assert_equal(insertion_list[0]['TestLocation'], 'Hyper-V')
        assert_equal(insertion_list[0]['HostName'], 'localhost')
        assert_equal(insertion_list[0]['HostVersion'], 'microsoft windows server 2012')
        assert_equal(insertion_list[0]['GuestOSType'], 'linux')
        assert_equal(insertion_list[0]['LISVersion'], '4.4.21-64-default')
        assert_equal(insertion_list[0]['TestCaseName'], 'external')
        assert_equal(insertion_list[0]['TestResult'], 'success')
        assert_equal(insertion_list[0]['TestArea'], 'Network')
        assert_equal(insertion_list[0]['TestDate'], '20160101')
