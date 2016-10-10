from nose.tools import assert_false
from nose.tools import assert_true
from unittest import TestCase
from lisa_parser.config import init_arg_parser
from lisa_parser.config import validate_input
from os import remove, path


class TestValidateInput(TestCase):
    def setUp(self):
        self.arg_parser = init_arg_parser()
        self.xml_file = path.join(path.dirname(__file__), 'test.xml')
        self.log_file = path.join(path.dirname(__file__), 'test.log')

        open(self.xml_file, 'a').close()
        open(self.log_file, 'a').close()

    def tearDown(self):
        remove(self.xml_file)
        remove(self.log_file)

    def test_valid_input(self):
        parsed_args = self.arg_parser.parse_args([
            self.xml_file,
            self.log_file
        ])

        assert_true(validate_input(parsed_args))

    def test_invalid_file_path(self):
        parsed_args = self.arg_parser.parse_args([
            'demo_files/notests.xml', 'demo_files/noica.log'
        ])

        assert_false(validate_input(parsed_args)[0])
