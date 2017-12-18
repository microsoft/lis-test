from utils import run_command
from shutil import rmtree
import os
import logging

logger=logging.getLogger(__name__)

class GitWrapper(object):
    base_cmd = ['git']

    def __init__(self, repo_path, remote_url=None):
        self.path = repo_path
        if remote_url:
            self.clone(remote_url, destination=repo_path)            


    def execute(self, arguments):
        return run_command(
            self.base_cmd + arguments,
            work_dir=self.path
        )

    @staticmethod
    def clone(remote_url, destination=""):
        return run_command(
            GitWrapper.base_cmd + [
                'clone', remote_url, destination
            ])
    
    def update_from_remote(self, local_branch, tag_name):
        self.execute(['checkout', 'master'])
        self.execute(['remote', 'update'])
        tag = self.execute(['tag', '-l', tag_name]).split()[-1]
        logger.info('Using tag %s' % tag)
        try:
            self.execute(['branch', '-D', local_branch])
        except RuntimeError:
            logger.warning('Unable to delete branch %s' % local_branch)
        self.execute(['checkout', '-b', local_branch, tag])

    def config(self, name, email):
        self.execute(['config', '--local', 'user.email', email])
        self.execute(['config', '--local', 'user.name', name])
    
    def add_files(self, file_list):
        self.execute(['add', '-u', '.'])
        for file in file_list: self.execute(['add', file])
    
    def commit(self, message):
        self.execute(['commit', '-m', message])

    def push(self, remote_addres, branch):
        self.execute(['push', remote_addres, branch])

    def add_remote(self, remote_name, remote_url):
        return self.execute([
            'remote', 'add', remote_name, remote_url
            ])
    
    def fetch(self, remote_name, tags=False):
        cmd = ['fetch']
        if tags: cmd.append("--tags")
        return self.execute(cmd.append(remote_name))

    def log_path(self, path, author=None, date=None, format='%H'):
        git_cmd = ['log']
        if author: git_cmd.extend(['--author', author])
        if date: git_cmd.extend(['--since', date])

        git_cmd.append('--pretty=format:{}'.format(format))
        git_cmd.extend(['--', path])

        return self.execute(git_cmd).splitlines()
    
    def create_patch(self, commit_id, destination):
        return self.execute([
            'format-patch', '-1', commit_id,
            '-o', destination
            ]).strip()
        
    def create_patches(self, commit_list, patch_folder):
        if os.path.exists(patch_folder): rmtree(patch_folder)
        os.mkdir(patch_folder)
        patch_list = []
        for commit_id in commit_list:
            try:
                patch_list.append(self.create_patch(commit_id, patch_folder))
            except RuntimeError as exc:
                logger.error('Unable to create a patch file for {}'.format(commit_id))
                logger.error(exc)

        return patch_list

    def get_commit_list(self, files_list, date='a day ago', author=None):
        commit_list = []
        commit_subjects = []

        for linux_path in files_list:
            logger.info('Searching for new commits in %s' % linux_path)            
            commits = self.log_path(linux_path, date=date, author=author)
            commit_subjects.extend(self.log_path(linux_path, date=date, author=author, format='%h---%s'))
            logger.info('%d new commits found' % len(commits))
            commit_list.extend(commits)

        if len(commit_list) > 0:
            logger.info('Selected the following commits:')
            [logger.info(subject) for subject in commit_subjects]
        else:
            logger.info('No new commits found')

        return set(commit_list)
