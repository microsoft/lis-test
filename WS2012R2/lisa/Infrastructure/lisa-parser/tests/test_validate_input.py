from config import validate_input
from config import init_arg_parser
from nose.tools import assert_false
from nose.tools import assert_true


class TestValidateInput():
    def setup(self):
        self.arg_parser = init_arg_parser()

    def test_valid_input(self):
        parsed_args = self.arg_parser.parse_args([
            'demo_files/test.xml', 'demo_files/ica.log'
        ])

        assert_true(validate_input(parsed_args))

    def test_invalid_file_path(self):
        parsed_args = self.arg_parser.parse_args([
            'demo_files/notests.xml', 'demo_files/noica.log'
        ])

        assert_false(validate_input(parsed_args))
