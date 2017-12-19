"""
Linux on Hyper-V and GCE Test Code, ver. 1.0.0
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
import re
import time
import logging

from googleapiclient import discovery
from oauth2client.client import GoogleCredentials
from oauth2client import GOOGLE_TOKEN_URI
from utils.cmdshell import SSHClient

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class GCPConnector:
    """
    Google Compute Platform connector that uses google-api-python-client.
    """
    def __init__(self, clientid=None, secret=None, token=None, projectid=None,
                 imageid=None, instancetype=None, user=None, localpath=None, zone=None):
        """
        Init GCE connector to create and configure instance VMs.
        :param clientid: client id from GCE API manager (create credentials API manager)
            https://developers.google.com/identity/protocols/application-default-credentials
        :param secret: client secret obtained from the GCE API manager
        :param token: refresh token obtained from gcloud sdk authentication
        :param imageid: GCE stores images based on predefined family keys; this should be provided
                        as stored in GCE should be provided: e.g. ubuntu-1604-lts
        :param instancetype: GCE hardware profile or vm size e.g. 'n1-highmem-16'
        :param user: remote ssh user for the VM
        :param localpath: localpath where the logs should be downloaded, and the
                            default path for other necessary tools
        :param zone: GCE global zone to connect to
        """
        self.credentials = GoogleCredentials(access_token=None, client_id=clientid,
                                             client_secret=secret, refresh_token=token,
                                             token_expiry=None, token_uri=GOOGLE_TOKEN_URI,
                                             user_agent='Python client library')

        self.compute = None
        self.storage = None

        self.instancetype = instancetype
        self.localpath = localpath
        self.host_key_file = os.path.join(self.localpath, 'known_hosts')
        if not zone:
            self.zone = 'us-west1-a'
        else:
            self.zone = zone
        self.region = re.match('([a-zA-Z]+-[a-zA-Z0-9]+)', self.zone).group(1)

        self.imageid = imageid
        self.projectid = projectid
        self.user = user

        self.key_name = 'test_ssh_key'
        self.bucket_name = 'middleware_bench' + str(time.time()).replace('.', '')
        self.net_name = 'middleware-bench-net' + str(time.time()).replace('.', '')
        self.subnet_name = 'middleware-bench-subnet' + str(time.time()).replace('.', '')

        self.vms = []

    def connect(self):
        """
        Obtain the GCE service clients by authenticating, and setup prerequisites like bucket,
        net, subnet and fw rules.
        """
        log.info('Creating compute client')
        self.compute = discovery.build('compute', 'v1', credentials=self.credentials,
                                       cache_discovery=False)

        # keeping bucket related code in case these will be later required
        # https://cloud.google.com/compute/docs/disks/gcs-buckets
        # self.storage = discovery.build('storage', 'v1', credentials=self.credentials)
        # log.info('Creating storage bucket {}'.format(self.bucket_name))
        # bucket_config = {'name': self.bucket_name,
        #                  'location': self.region
        #                 }
        # bucket = self.storage.buckets().insert(project=self.projectid,
        #                                        body=bucket_config).execute()

        log.info('Creating virtual network: {}'.format(self.net_name))
        net_config = {'name': self.net_name,
                      'autoCreateSubnetworks': False
                      }
        net = self.compute.networks().insert(project=self.projectid, body=net_config).execute()
        self.wait_for_operation(net['name'])
        log.info(net)
        log.info('Creating subnet: {}'.format(self.subnet_name))
        subnet_config = {'name': self.subnet_name,
                         'ipCidrRange': '10.10.10.0/24',
                         'network': net['targetLink']
                         }
        subnet = self.compute.subnetworks().insert(project=self.projectid, region=self.region,
                                                   body=subnet_config).execute()
        self.wait_for_operation(subnet['name'], region=self.region)
        log.info(subnet)

        log.info('Creating firewall rules.')
        fw_config = {'name': 'all-traffic-' + self.net_name,
                     'network': net['targetLink'],
                     'allowed': [{'IPProtocol': 'tcp',
                                  'ports': ['22']},
                                 {'IPProtocol': 'tcp',
                                  'ports': ['0-65535']},
                                 {'IPProtocol': 'udp',
                                  'ports': ['0-65535']},
                                 {'IPProtocol': 'icmp'}]
                     }
        fw = self.compute.firewalls().insert(project=self.projectid, body=fw_config).execute()
        self.wait_for_operation(fw['name'])
        log.info(fw)

    def create_vm(self):
        """
        Create an GCE VM instance.
        :return: VirtualMachine object
        """
        vm_name = self.imageid.lower() + '-' + str(time.time()).replace('.', '')
        log.info('Creating instance: {}'.format(vm_name))
        image = self.compute.images().getFromFamily(project='ubuntu-os-cloud',
                                                    family=self.imageid).execute()
        machine_type = 'zones/{}/machineTypes/{}'.format(self.zone, self.instancetype)
        with open(os.path.join(self.localpath, self.key_name + '.pub'), 'r') as f:
            key_data = f.read()
        vm_config = {'name': vm_name,
                     'machineType': machine_type,
                     'disks': [{'boot': True,
                                'autoDelete': True,
                                'initializeParams': {'sourceImage': image['selfLink']}}],
                     'networkInterfaces': [{'network': 'global/networks/{}'.format(self.net_name),
                                            'subnetwork': 'regions/{}/subnetworks/{}'.format(
                                                    self.region, self.subnet_name),
                                            'accessConfigs': [{'type': 'ONE_TO_ONE_NAT',
                                                               'name': 'External NAT'}]}],
                     'serviceAccounts': [
                         {'email': 'default',
                          'scopes': ['https://www.googleapis.com/auth/devstorage.read_write',
                                     'https://www.googleapis.com/auth/logging.write']}],
                     'metadata': {'items': [
                         # {'key': 'bucket',
                         #  'value': self.bucket_name},
                         {'key': 'ssh-keys',
                          'value': '{user}:{key} {user}'.format(user=self.user, key=key_data)},
                     ]}}
        create_vm = self.compute.instances().insert(project=self.projectid, zone=self.zone,
                                                    body=vm_config).execute()
        self.wait_for_operation(create_vm['name'], zone=self.zone)

        start_vm = self.compute.instances().start(instance=vm_name, project=self.projectid,
                                                  zone=self.zone).execute()
        self.wait_for_operation(start_vm['name'], zone=self.zone)

        vm_details = self.compute.instances().get(instance=vm_name, project=self.projectid,
                                                  zone=self.zone).execute()
        log.info('VM {} details are: {}'.format(vm_name, vm_details))
        self.vms.append(vm_details)

        return vm_details

    def attach_disk(self, vm_name, disk_size):
        """
        Creates and attached a disk to VM.
        :param vm_name: VM name to attach the disk to
        :param disk_size: disk size in GB
        :return disk_name: given disk name
        """
        disk_name = 'disk-' + str(time.time()).replace('.', '')
        log.info('Creating disk {}'.format(disk_name))
        disk_config = {'name': disk_name,
                       'sizeGb': disk_size,
                       'zone': 'projects/{}/zones/{}'.format(self.projectid, self.zone),
                       'type': 'projects/{}/zones/{}/diskTypes/pd-ssd'.format(self.projectid,
                                                                              self.zone)}

        create_disk = self.compute.disks().insert(project=self.projectid, zone=self.zone,
                                                  body=disk_config).execute()
        log.info(create_disk)
        self.wait_for_operation(create_disk['name'], zone=self.zone)

        log.info('Attaching disk {} to VM {}'.format(disk_name, vm_name))
        source_config = {
            'source': '/compute/v1/projects/{}/zones/{}/disks/{}'.format(self.projectid,
                                                                         self.zone, disk_name),
            'autoDelete': True
        }
        attach_disk = self.compute.instances().attachDisk(instance=vm_name, project=self.projectid,
                                                          zone=self.zone,
                                                          body=source_config).execute()
        log.info(attach_disk)
        self.wait_for_operation(attach_disk['name'], zone=self.zone)

        return disk_name

    def wait_for_operation(self, operation, zone=None, region=None):
        """
       Check when an GCE operation is finished.
       :param operation: the GCE operation name
       :param zone: zone of the operation(optional - default to global operations)
       :param region: region of the operation(optional - default to global operations)
       :return: result zoneOperations status response
       """
        log.info('Waiting for operation {} to finish...'.format(operation))
        while True:
            time.sleep(10)
            if zone:
                result = self.compute.zoneOperations().get(project=self.projectid, zone=zone,
                                                           operation=operation).execute()
            elif region:
                result = self.compute.regionOperations().get(project=self.projectid, region=region,
                                                             operation=operation).execute()
            else:
                result = self.compute.globalOperations().get(project=self.projectid,
                                                             operation=operation).execute()

            if result.get('status', None) == 'DONE':
                if 'error' in result:
                    raise Exception(result['error'])
                return result

    def wait_for_ping(self, instance):
        """
        To obtain the SSH client, we must wait for the instance to boot, even the GCE instance
        status is available.
        :param instance: instance to wait for sshd start
        :return: SSHClient or None on error
        """
        host_key_file = os.path.join(self.localpath, 'known_hosts')
        ping_arg = '-n'
        if os.name == 'posix':
            ping_arg = '-c'
        nat_ip = instance['networkInterfaces'][0]['accessConfigs'][0].get('natIP', None)
        if not nat_ip:
            log.error("Spawned instance was not allocated a NAT IP. Please try again.")
            raise
        ping_cmd = 'ping {} 1 {}'.format(ping_arg, nat_ip)
        try:
            timeout = 0
            while os.system(ping_cmd) != 0 or timeout >= 60:
                time.sleep(5)
                timeout += 5
            # artificial wait for ssh service up status
            time.sleep(30)
            open(host_key_file, 'w').close()
            client = SSHClient(server=nat_ip, host_key_file=self.host_key_file, user=self.user,
                               ssh_key_file=os.path.join(self.localpath, self.key_name + '.pem'))
        except Exception as e:
            log.error(e)
            raise
        return client

    def restart_vm(self, instance):
        """
        Restart instances VM.
        :param instance instance obj to restart
        :return SSHClient
        """
        reset_vm = self.compute.instances().reset(instance=instance['name'],
                                                  project=self.projectid, zone=self.zone).execute()
        self.wait_for_operation(reset_vm['name'], zone=self.zone)

        log.info('Rebooting VM: {}'.format(instance['name']))
        return self.wait_for_ping(instance)

    def teardown(self):
        """
        Cleanup created instances and devices.
        """
        log.info("Running teardown.")
        for vm in self.vms:
            delete_vm = self.compute.instances().delete(project=self.projectid, zone=self.zone,
                                                        instance=vm['name']).execute()
            self.wait_for_operation(delete_vm['name'], zone=self.zone)
            log.info("Deleted: {}".format(vm['name']))

        log.info('Cleaning up FW rules')
        delete_op = self.compute.firewalls().delete(project=self.projectid,
                                                    firewall='all-traffic-' +
                                                             self.net_name).execute()
        self.wait_for_operation(delete_op['name'])
        log.info('Cleaning up subnetworks')
        delete_op = self.compute.subnetworks().delete(project=self.projectid, region=self.region,
                                                      subnetwork=self.subnet_name).execute()
        self.wait_for_operation(delete_op['name'], region=self.region)
        log.info('Cleaning up networks')
        delete_op = self.compute.networks().delete(project=self.projectid,
                                                   network=self.net_name).execute()
        self.wait_for_operation(delete_op['name'])
        # log.info('Cleaning up storage bucket')
        # self.storage.buckets().delete(name=self.bucket_name).execute()
