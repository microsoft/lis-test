import subprocess
import logging
import fileinput
import re

logger=logging.getLogger(__name__)

def normalize_path(patch_path, normalize_dict):
    templates = ['--- a/{}', '+++ b{}']

    for search, replace in normalize_dict.items():
        for template in templates:
            for line in fileinput.input(patch_path, inplace=True):
                print line.replace(template.format(search), template.format(replace)),

def apply_patch(build_folder, patch_file):
    cmd = ['patch', '-f', '-i', patch_file]
    return run_command(cmd, build_folder)

def parse_results(response_data, expected_tests):
    regex_pattern = re.compile('^\s+Test\s([A-Za-z0-9\-\_]+)\s+:\s([A-Za-z]+)')

    test_results = {}
    for line in response_data:
        result = regex_pattern.search(line)
        if result:
            if result.group(1) in expected_tests:
                test_results[result.group(1)] = result.group(2)

    return test_results

def get_commit_info(patch_path):
    commit_id = None
    commid_desc = None
    with open(patch_path, 'r') as patch_info:
        for index, line in enumerate(patch_info):
            if index == 0:
                commit_id = line.strip().split()[1]
            elif index == 3:
                commid_desc = line.strip().split('Subject:')[1].strip()
            elif index > 4:
                break
    
    return commit_id, commid_desc

def build(build_folder, clean=False):
    base_build_cmd = ['cd', build_folder, '&&', 'make', '-C']
    drivers = '/lib/modules/$(uname -r)/build M=$(pwd)'
    daemons = './tools'
    # First run the clean commands
    run_command(base_build_cmd + [drivers, 'clean'])
    run_command(base_build_cmd + [daemons, 'clean'])
    
    if not clean:
        run_command(base_build_cmd + [drivers])
        run_command(base_build_cmd + [daemons])

def run_command(command_arguments, work_dir='./'):
    ps_command = subprocess.Popen(
    command_arguments,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    cwd=work_dir
    )
    logger.debug('Running command {}'.format(command_arguments))
    stdout_data, stderr_data = ps_command.communicate()

    logger.debug('Command output %s', stdout_data)
    if ps_command.returncode != 0:
        raise RuntimeError(
            "Command failed, status code %s stdout %r stderr %r" % (
                ps_command.returncode, stdout_data, stderr_data
            ), stdout_data, stderr_data
        )
    else:
        return stdout_data
