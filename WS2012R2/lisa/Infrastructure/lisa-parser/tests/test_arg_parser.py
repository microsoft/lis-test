from nose.tools import assert_equals
from os import path
from lisa_parser.config import init_arg_parser


def test_default_usage():
    parsed_arguments = init_arg_parser().parse_args(
        ['xmlfilepath', 'logfilepath']
    )
    assert_equals(parsed_arguments.xml_file_path, 'xmlfilepath')
    assert_equals(parsed_arguments.log_file_path, 'logfilepath')
    assert_equals(parsed_arguments.skipkvp, False)
    assert_equals(parsed_arguments.loglevel, 2)
    assert_equals(parsed_arguments.perf, False)
    assert_equals(parsed_arguments.snapshot, False)
    assert_equals(
        parsed_arguments.config,
        path.join(
            path.split(path.dirname(__file__))[0],
            'config\\db.config'
        )
    )


def test_full_arguments_list():
    parsed_arguments = init_arg_parser().parse_args(
        ['xmlfilepath', 'logfilepath', '-k', '-c', 'config', '-l', '3',
         '-p', 'perflogpath', '-s', 'snapshot']
    )

    assert_equals(parsed_arguments.xml_file_path, 'xmlfilepath')
    assert_equals(parsed_arguments.log_file_path, 'logfilepath')
    assert_equals(parsed_arguments.skipkvp, True)
    assert_equals(parsed_arguments.loglevel, 3)
    assert_equals(parsed_arguments.config, 'config')
    assert_equals(parsed_arguments.perf, 'perflogpath')
    assert_equals(parsed_arguments.snapshot, 'snapshot')


def test_full_name_arguments_list():
    parsed_arguments = init_arg_parser().parse_args(
        ['xmlfilepath', 'logfilepath', '--skipkvp',
         '--config', 'config', '--loglevel', '3',
         '--perf', 'perflogpath', '--snapshot', 'snapshot']
    )

    assert_equals(parsed_arguments.xml_file_path, 'xmlfilepath')
    assert_equals(parsed_arguments.log_file_path, 'logfilepath')
    assert_equals(parsed_arguments.skipkvp, True)
    assert_equals(parsed_arguments.loglevel, 3)
    assert_equals(parsed_arguments.config, 'config')
    assert_equals(parsed_arguments.perf, 'perflogpath')
    assert_equals(parsed_arguments.snapshot, 'snapshot')
