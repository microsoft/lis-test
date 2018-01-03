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

import constants

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def host_type(provider):
    """
    Return host type by provider
    :param provider: cloud provider
    :return: Host type string
    """
    if provider == constants.AWS:
        return constants.HVM
    elif provider == constants.AZURE:
        return constants.MSAZURE
    elif provider == constants.GCE:
        return constants.KVM


def data_path(sriov):
    """
    Return data path based on sriov state
    :param sriov: sriov state
    :return: Data path string
    """
    if sriov == constants.ENABLED:
        return constants.SRIOV
    else:
        return constants.SYNTHETIC


def run_sql(sql, server, db=None, user=None, password=None):
    """
    Return SQL command to run on Windows
    :param sql: sql file script
    :param server: server instance
    :param user: db user
    :param password: db password
    :param db: database to execute sql on
    :return: SQL command
    """
    if not user:
        user = constants.MSSQL_USER
    cmd = 'Invoke-Sqlcmd -InputFile \'{}\' -ServerInstance {} -Username {} -Password {}'.format(
            sql, server, user, password)
    if db:
        cmd += ' -Database {}'.format(db)
    return cmd
