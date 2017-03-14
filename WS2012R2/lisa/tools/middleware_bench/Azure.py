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

import os
import time
import logging

from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.compute import ComputeManagementClient

from msrestazure.azure_exceptions import CloudError

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class AzureConnector:
    """
    Azure connector that uses azure-sdk-for-python plugin.
    """
    def __init__(self, clientid=None, secret=None, subscriptionid=None, tenantid=None,
                 imageid=None, instancetype=None, user=None, localpath=None, location=None):
        """
        Init Azure connector to create and configure instance VMs.
        :param clientid: client id obtained from Azure AD application (create key)
            https://docs.microsoft.com/en-us/azure/azure-resource-manager/
            resource-group-create-service-principal-portal
        :param secret: client secret obtained from the Azure AD application
        :param subscriptionid: Azure subscription id
        :param tenantid: Azure tenant/directory id
        :param imageid: Azure requires multiple image references (publisher, offer, sku, version),
            for simplicity only the offer and sku should be provided: e.g. UbuntuServer#16.04.0-LTS
        :param instancetype: Azure hardware profile or vm size e.g. 'Standard_DS1'
        :param user: remote ssh user for the VM
        :param localpath: localpath where the logs should be downloaded, and the
                            default path for other necessary tools
        :param location: Azure global location to connect to
        """
        credentials = ServicePrincipalCredentials(client_id=clientid, secret=secret,
                                                  tenant=tenantid)

        self.resource_client = ResourceManagementClient(credentials, subscriptionid)
        self.compute_client = ComputeManagementClient(credentials, subscriptionid)
        self.storage_client = StorageManagementClient(credentials, subscriptionid)
        self.network_client = NetworkManagementClient(credentials, subscriptionid)

        self.instancetype = instancetype
        self.localpath = localpath
        self.host_key_file = os.path.join(self.localpath, 'known_hosts')
        if not location:
            self.location = 'westus'
        else:
            self.location = location

        if 'Ubuntu' in imageid:
            self.imageid = {'publisher': 'Canonical',
                            'offer': imageid.split('#')[0],
                            'sku': imageid.split('#')[1],
                            'version': 'latest'
                            }

        self.user = user
        self.dns_suffix = '.{}.cloudapp.azure.com'.format(self.location)
        self.key_name = 'test_ssh_key'
        self.group_name = 'middleware_bench'
        self.vmnet_name = 'middleware_bench_vmnet'
        self.subnet_name = 'middleware_bench_subnet'
        self.os_disk_name = 'middleware_bench_osdisk'
        self.storage_account = 'benchstor' + str(time.time()).replace('.', '')
        self.ip_config_name = 'middleware_bench_ipconfig'
        self.nic_name = 'middleware_bench_nic'

        self.subnet = None
        self.vms = []

    def azure_connect(self):
        """
        Obtain the Azure connector by authenticating. This also creates the keypair and
        security group for the instance.
        """
        log.info('Creating/updating resource group: {} with location: {}'.format(self.group_name,
                                                                                 self.location))
        self.resource_client.resource_groups.create_or_update(self.group_name,
                                                              {'location': self.location})

        log.info('Creating storage account: {}'.format(self.storage_account))
        storage_op = self.storage_client.storage_accounts.create(self.group_name,
                                                                 self.storage_account,
                                                                 {'sku': {'name': 'premium_lrs'},
                                                                  'kind': 'storage',
                                                                  'location': self.location})
        storage_op.wait()

        log.info('Creating virtual network: {}'.format(self.vmnet_name))
        create_vmnet = self.network_client.virtual_networks.create_or_update(
                self.group_name, self.vmnet_name,
                {'location': self.location,
                 'address_space': {'address_prefixes': ['10.10.0.0/16']}})
        create_vmnet.wait()

        log.info('Creating subnet: {}'.format(self.subnet_name))
        create_subnet = self.network_client.subnets.create_or_update(
                self.group_name, self.vmnet_name, self.subnet_name,
                {'address_prefix': '10.10.10.0/24'})
        self.subnet = create_subnet.result()

    def azure_create_vm(self):
        """
        Create an Azure VM instance.
        :return: VirtualMachine object
        """
        log.info('Creating VM: {}'.format(self.imageid))
        vm_name = self.imageid['offer'].lower() + str(time.time()).replace('.', '')
        nic = self.create_nic(vm_name)
        with open(os.path.join(self.localpath, self.key_name + '.pub'), 'r') as f:
            key_data = f.read()
        vm_parameters = {
            'location': self.location,
            'os_profile': {
                'computer_name': vm_name,
                'admin_username': self.user,
                'linux_configuration': {
                    'disable_password_authentication': True,
                    'ssh': {
                        'public_keys': [{
                            'path': '/home/{}/.ssh/authorized_keys'.format(self.user),
                            'key_data': key_data}]}}},
            'hardware_profile': {'vm_size': self.instancetype},
            'storage_profile': {
                'image_reference': {
                    'publisher': self.imageid['publisher'],
                    'offer': self.imageid['offer'],
                    'sku': self.imageid['sku'],
                    'version': self.imageid['version']},
                'os_disk': {
                    'name': self.os_disk_name,
                    'caching': 'None',
                    'create_option': 'fromImage',
                    'vhd': {'uri': 'https://{}.blob.core.windows.net/vhds/{}.vhd'.format(
                            self.storage_account, self.vmnet_name + str(time.time()))}}},
            'network_profile': {'network_interfaces': [{'id': nic.id}]}
        }
        vm_creation = self.compute_client.virtual_machines.create_or_update(
                self.group_name, vm_name, vm_parameters)
        vm_creation.wait()

        vm_instance = self.compute_client.virtual_machines.get(self.group_name, vm_name)

        log.info('Starting VM: {}'.format(vm_name))
        vm_start = self.compute_client.virtual_machines.start(self.group_name, vm_name)
        vm_start.wait()
        log.info('Started VM: {}'.format(vm_instance.__dict__))

        self.vms.append(vm_instance)

        return vm_instance

    def create_nic(self, vm_name):
        """
        Create an VM Network interface.
        :return: NetworkInterface ClientRawResponse
        """
        log.info('Creating VM network interface: {}'.format(self.nic_name))
        create_public_ip = self.network_client.public_ip_addresses.create_or_update(
                self.group_name, vm_name + '-ip',
                {'location': self.location,
                 'public_ip_allocation_method': 'Dynamic',
                 'public_ip_address_version': 'IPv4',
                 'dns_settings': {
                     'domain_name_label': vm_name}})
        public_ip = create_public_ip.result()

        nic_op = self.network_client.network_interfaces.create_or_update(
                self.group_name, self.nic_name + str(time.time()),
                {'location': self.location,
                 'ip_configurations': [{'name': self.ip_config_name,
                                        'subnet': {'id': self.subnet.id},
                                        'public_ip_address': {'id': public_ip.id}
                                        }]
                 })
        return nic_op.result()

    def attach_disk(self, vm_instance, disk_size, lun=0):
        """
        Creates and attached a disk to VM.
        :param vm_instance: VirtualMachine obj to attach the disk to
        :param disk_size: disk size in GB
        :param lun: disk lun
        :return disk_name: given disk name
        """
        disk_name = vm_instance.name + '_disk_' + str(time.time())
        disk_profile = {'name': disk_name,
                        'disk_size_gb': disk_size,
                        'caching': 'None',
                        'lun': lun,
                        'vhd': {'uri': "http://{}.blob.core.windows.net/vhds/{}.vhd".format(
                                self.storage_account, disk_name)},
                        'create_option': 'Empty'}

        vm_instance.storage_profile.data_disks.append(disk_profile)
        vm_update = self.compute_client.virtual_machines.create_or_update(self.group_name,
                                                                          vm_instance.name,
                                                                          vm_instance)
        vm_update.wait()
        try:
            log.info(vm_update.result())
        except Exception as de:
            log.info(de)
        return disk_name

    def teardown(self):
        """
        Cleanup created instances and devices.
        """
        log.info("Running teardown.")
        # Delete Resource group and everything in it
        delete_resource_group = self.resource_client.resource_groups.delete(self.group_name)
        try:
            delete_resource_group.wait()
        except CloudError as ce:
            log.info(ce)
            if 'AuthorizationFailed' in ce:
                log.info("Resource group {} already removed".format(self.group_name))
        log.info("Deleted: {}".format(self.group_name))
