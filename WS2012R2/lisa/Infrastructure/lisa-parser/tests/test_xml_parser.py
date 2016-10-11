from unittest import TestCase
from os import remove, path
from create_files import create_xml_file
from lisa_parser.file_parser import ParseXML


class TestXMLParser(TestCase):
    def setUp(self):
        self.file_path = path.join(path.dirname(__file__), 'test.xml')
        create_xml_file(self.file_path)
        self. xml_obj = ParseXML(self.file_path)
        self.maxDiff = None

    def tearDown(self):
        remove(self.file_path)

    def test_get_suite(self):
        self.assertEquals(self.xml_obj.get_tests_suite(), 'Network')

    def test_get_tests(self):
        self.assertDictEqual(
            self.xml_obj.get_tests(),
            {
                'external': {
                    'setupscript': ['setupScript'],
                    'testparams': [('NIC', 'nicSetup'), ('TC_COVERED', 'NET-02')],
                    'files': ['path_to_file1,path_to_file2']
                }
            }
        )

    def test_get_vms(self):
        self.assertDictEqual(
            self.xml_obj.get_vms(),
            {
                'vmname': {
                    'hvServer': 'localhost',
                    'os': 'linux'
                }
            }
        )

    def test_parse_from_string(self):
        pass
