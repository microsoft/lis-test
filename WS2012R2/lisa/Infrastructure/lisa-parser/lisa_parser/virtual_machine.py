"""
Linux on Hyper-V and Azure Test Code, ver. 1.0.0
Copyright (c) Microsoft Corporation

All rights reserved
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the Apache Version 2.0 License for specific language governing
permissions and limitations under the License.
"""

import logging
from file_parser import ParseXML
import subprocess
import time
import sys

logger = logging.getLogger(__name__)


class VirtualMachine(object):
    """Holds specific logic for interacting with a virtual machine

    The class is used to save details regarding a vm on which a test has been
    ran and also executes methods that interact and get data from that specific
    vm.
    """

    def __init__(self, vm_name, hv_server, os=None, host_os=None, checkpoint_name='icabase', check=True):
        self.vm_name = vm_name
        self.hv_server = hv_server
        self.os = os
        self.host_os = host_os
        self.kvp_info = dict()
        self.location = ''
        self.checkpoint_name = checkpoint_name
        """Check if VM exists"""
        if check:
            self.check_if_exists()

    def check_if_exists(self):
        self.invoke_ps_command(
            'get'
        )

    def start(self):
        self.invoke_ps_command(
            'start'
        )

    def revert_snapshot(self):
        if self.checkpoint_name:
            self.invoke_ps_command(
                'revert'
            )
        else:
            logger.warning(
                "Checkpoint name was not set for %s. No revert will be performed" % self.vm_name
            )

    def update_from_kvp(self, kvp_fields, stop_vm):
        if not self.get_status():
            try:
                self.revert_snapshot()
            except RuntimeError:
                logger.warning("Unable to restore VM snapshot")
            self.start()
            logger.info('Starting %s - Waiting for it to boot', self.vm_name)
            if not self.has_booted():
                logger.error('%s was unable to boot', self.vm_name)
                logger.info('Terminating execution')
                sys.exit(0)

        logger.info('Running KVP command on %s for the following fields %s',
                    self.vm_name, kvp_fields)
        self.kvp_info = self.get_kvp_dict(kvp_fields)

        if stop_vm:
            logging.info('Stopping execution for %s', self.vm_name)
            self.stop()

    def stop(self):
        self.invoke_ps_command(
            'stop'
        )

    def get_status(self):
        vm_state = self.invoke_ps_command(
            'check'
        )
        if vm_state.strip().lower() == 'off':
            logger.debug('%s is turned off', self.vm_name)
            return False
        else:
            logger.debug('%s is running', self.vm_name)
            return True

    def get_kvp_dict(self, kvp_fields=None):
        cmd_output = self.invoke_ps_command('kvp')
        if not kvp_fields:
            return VirtualMachine.parse_kvp_output(cmd_output)

        kvp_dict = VirtualMachine.parse_kvp_output(cmd_output)
        kvp_values = dict()
        for field in kvp_fields:
            try:
                kvp_values[field] = kvp_dict[field]
            except KeyError:
                logger.warning('Unable to find kvp value for %s', field)

        return kvp_values

    def has_booted(self, timeout=180, searched_field='OSName'):
        is_booting = True
        start = time.time()
        vm_info = dict()
        logger.debug('Waiting for successful boot')
        logger.debug('Boot timeout value - %s', timeout)

        while is_booting:
            vm_info = self.get_kvp_dict()
            logger.debug('KVP output - %s', vm_info)
            if searched_field in vm_info.keys():
                is_booting = False
                continue

            current_time = time.time()
            if int(current_time - start) > timeout:
                is_booting = False
                vm_info = False
                continue

        return vm_info

    def invoke_ps_command(self, cmd_type):
        cmd_args = [
            'powershell', 'cmd', '-Name', self.vm_name, '-ComputerName',
            self.hv_server
        ]

        if cmd_type == 'start':
            cmd_args[1] = 'start-vm'
        elif cmd_type == 'get':
            cmd_args[1] = 'get-vm'
        elif cmd_type == 'stop':
            cmd_args[1] = 'stop-vm -turnoff'
        elif cmd_type == 'check':
            cmd_args[1] = 'get-vm'
            cmd_args.insert(1, '(')
            cmd_args.append(').State')
        elif cmd_type == 'revert':
            cmd_args = [
                'powershell', 'Restore-VMSnapshot', '-Name',
                self.checkpoint_name, '-VMName', self.vm_name, '-ComputerName',
                self.hv_server, '-Confirm:$false'
            ]
        elif cmd_type == 'kvp':
            query_strings = [
                '"' + "Select * From Msvm_ComputerSystem where ElementName='" +
                self.vm_name + "'" + '";',
                '"' + "Associators of {$vm} Where AssocClass=Msvm_SystemDevice "
                "ResultClass=Msvm_KvpExchangeComponent" + '"'
            ]
            cmd_args = [
                'powershell', '$vm', '=', 'Get-WmiObject', '-ComputerName',
                self.hv_server, '-Namespace', "root\\virtualization\\v2", '-Query',
                query_strings[0], '(', 'Get-WmiObject', '-ComputerName',
                self.hv_server,
                '-Namespace', 'root\\virtualization\\v2', '-Query',
                query_strings[1], ').GuestIntrinsicExchangeItems'
            ]

        try:
            return VirtualMachine.execute_command(cmd_args)
        except RuntimeError:
            logger.error('Error on running powershell command', exc_info=True)
            logger.info('Terminating execution')
            sys.exit(0)

    @staticmethod
    def parse_kvp_output(cmd_output):
        kvp_output = dict()
        for value in cmd_output.split('\r\n')[:-1]:
            result_tuple = ParseXML.parse_from_string(value)
            kvp_output.update({
                result_tuple[0]: result_tuple[1]
            })

        return kvp_output

    @staticmethod
    def execute_command(command_arguments):
        ps_command = subprocess.Popen(
            command_arguments,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        stdout_data, stderr_data = ps_command.communicate()

        logger.debug('Command output %s', stdout_data)
        if ps_command.returncode != 0:
            raise RuntimeError(
                "Command failed, status code %s stdout %r stderr %r" % (
                    ps_command.returncode, stdout_data, stderr_data
                )
            )
        else:
            return stdout_data
0
