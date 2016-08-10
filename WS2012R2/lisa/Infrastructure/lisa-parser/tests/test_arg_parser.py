from config import init_arg_parser
from nose.tools import assert_equals


def test_default_usage():
    parsed_arguments = init_arg_parser().parse_args(
        ['xmlfilepath', 'logfilepath']
    )
    assert_equals(parsed_arguments.xml_file_path, 'xmlfilepath')
    assert_equals(parsed_arguments.log_file_path, 'logfilepath')
    assert_equals(parsed_arguments.skipkvp, False)
    assert_equals(parsed_arguments.loglevel, 2)
    assert_equals(parsed_arguments.perf, False)
    assert_equals(parsed_arguments.config, 'config/db.config')


def test_full_arguments_list():
    parsed_arguments = init_arg_parser().parse_args(
        ['xmlfilepath', 'logfilepath', '-k', '-c', 'config', '-l', '3',
         '-p', 'perflogpath']
    )

    assert_equals(parsed_arguments.xml_file_path, 'xmlfilepath')
    assert_equals(parsed_arguments.log_file_path, 'logfilepath')
    assert_equals(parsed_arguments.skipkvp, True)
    assert_equals(parsed_arguments.loglevel, 3)
    assert_equals(parsed_arguments.config, 'config')
    assert_equals(parsed_arguments.perf, 'perflogpath')


def test_full_name_arguments_list():
    parsed_arguments = init_arg_parser().parse_args(
        ['xmlfilepath', 'logfilepath', '--skipkvp',
         '--config', 'config', '--loglevel', '3',
         '--perf', 'perflogpath']
    )

    assert_equals(parsed_arguments.xml_file_path, 'xmlfilepath')
    assert_equals(parsed_arguments.log_file_path, 'logfilepath')
    assert_equals(parsed_arguments.skipkvp, True)
    assert_equals(parsed_arguments.loglevel, 3)
    assert_equals(parsed_arguments.config, 'config')
    assert_equals(parsed_arguments.perf, 'perflogpath')
