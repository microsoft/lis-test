import argparse
import os
from shutil import rmtree
LIS_NEXT_REPO_URL = 'https://github.com/LIS/lis-next.git'
LINUX_REPO_URL = 'https://github.com/torvalds/linux.git'
LINUX_NEXT_REMOTE = 'https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git'
BUILDS_PATH = '/root/builds'
FAILURES_PATH = '/root/failed'

FILES_MAP = {
    "drivers/hv": "hv/",
    "tools/hv": "hv/tools/",
    "drivers/net/hyperv": "hv/"
}

def path(path):
    if not os.path.exists(path):
        raise ValueError('Path %s does not exists' % path)
    else:
        return path
    
class PathAction(argparse.Action):
    def __call__(self, parser, namespace, values, option_string):
        action = parser.prog.split()[1]
        if self.dest == 'failures_path':
            if not os.path.exists(values):
                os.mkdir(values)
            values = os.path.join(values, action)
        
        if os.path.exists(values):
            rmtree(values)

        os.mkdir(values)
        setattr(namespace, self.dest, values) 


def get_arg_parser():
    #TODO: Add common argument to a parent parser
    parser = argparse.ArgumentParser()
    sub_parsers = parser.add_subparsers(help='CLI Commands')
    
    create_patch = sub_parsers.add_parser(
        'create', 
        help='Create patch files from previous commits'
    )
    create_patch.add_argument(
        '-d', '--date',
        help='Date used to check commit history',
        default="1 day ago")
    create_patch.add_argument(
        '-a', '--author',
        help='Specific commit author',
        default=None
    )
    create_patch.add_argument(
        '-l', '--linux-repo',
        help='Directory containing a local linux repository',
        default='None'
    )
    create_patch.add_argument(
        '-p', '--patches-folder',
        help='Location of the patch files',
        default='./patches',
        action=PathAction
    )
    create_patch.add_argument(
        '-t', '--remote_tag',
        help='Tag name',
        default='next-*'
    )
    create_patch.add_argument(
        '-b', '--branch',
        help='Local branch name',
        default='patch-automation'
    )
    create_patch.add_argument(
        '-m', '--files_map',
        help='JSON file containing a mapping between linux tree and project tree',
        default='./map.json'
    )
    create_patch.add_argument(
        '-f', '--find',
        help='Perform find step',
        action='store_true',
        default=False
    )
    
    apply_patches = sub_parsers.add_parser('apply', help='Apply patches on a specified build')
    apply_patches.add_argument(
        'patches_folder',
        help='Location of the patch files that will be applied',
        type=path
    )
    apply_patches.add_argument(
        '-p', '--project',
        help='Remote repository that will be cloned',
        default=LIS_NEXT_REPO_URL
    )
    apply_patches.add_argument(
        '-b', '--builds-path',
        help='Location where the new builds will be saved',
        default=BUILDS_PATH,
        action=PathAction
    )
    apply_patches.add_argument(
        '-f', '--failures-path',
        help='Directory where failed attempts will be copied',
        default='/root/failed',
        action=PathAction
    )
    apply_patches.add_argument(
        '-n', '--normalize-paths',
        help='File containing a mapping between linux paths and project paths',
        default='file-map.json'
    )
    compile_patches = sub_parsers.add_parser('compile', help='Compile projects')
    compile_patches.add_argument(
        'builds_path',
        help='Location of the builds that will be compiled',
        type=path
    )
    compile_patches.add_argument(
        '-f', '--failures-path',
        help='Directory where failed attempts will be copied',
        default='/root/failed',
        action=PathAction
    )

    commit_patches = sub_parsers.add_parser('commit', help='Commit patches')
    commit_patches.add_argument(
        'builds_folder',
        type=path
    )
    commit_patches.add_argument(
        '-r', '--remote-url'
    )
    commit_patches.add_argument(
        '-f', '--patch-files'
    )
    commit_patches.add_argument(
        '-e', '--email'
    )
    commit_patches.add_argument(
        '-b', '--branch',
        default='master'
    )
    commit_patches.add_argument(
        '-n', '--name'
    )
    commit_patches.add_argument(
        '-p', '--password'
    )
    commit_patches.add_argument(
        '-u', '--username'
    )

    log_parser = sub_parsers.add_parser('parse', help='Parse boot results')
    log_parser.add_argument(
        'results_path',
        type=path
    )
    log_parser.add_argument(
        '-f', '--failures-path',
        help='Directory where failed attempts will be copied',
        default='/root/failed'
    )
    log_parser.add_argument(
        '-b', '--builds-path',
        help='Location where the new builds will be saved',
        default=BUILDS_PATH
    )

    server = sub_parsers.add_parser('serve', help='Start patch server')
    server.add_argument(
        'expected_requests', 
        type=int,
        help='Number of POST requests expected'
    )
    server.add_argument(
        '-a', '--address',
        default='0.0.0.0'
    )
    server.add_argument(
        '-p', '--port',
        default=80,
        type=int
    )
    server.add_argument(
        '-b', '--builds-path',
        help='Location where the new builds will be saved',
        default=BUILDS_PATH
    )
    server.add_argument(
        '-f', '--failures-path',
        help='Directory where failed attempts will be copied',
        default='/root/failed',
        action=PathAction
    )

    return parser
