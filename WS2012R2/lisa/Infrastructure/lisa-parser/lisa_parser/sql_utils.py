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
from envparse import env
import logging
import pyodbc
from string import Template
import sys

logger = logging.getLogger(__name__)


def init_connection():
    connection = pyodbc.connect(get_connection_string())
    return connection, connection.cursor()


def get_connection_string():
    """Constructs the connection string for the DB with values from env file

    """

    connection_string = Template("Driver={$SQLDriver};"
                                 "Server=$server,$port;"
                                 "Database=$db_name;"
                                 "Uid=$db_user;"
                                 "Pwd=$db_password;"
                                 "Encrypt=$encrypt;"
                                 "TrustServerCertificate=$certificate;"
                                 "Connection Timeout=$timeout;")

    return connection_string.substitute(
        SQLDriver=env.str('Driver'),
        server=env.str('Server'),
        port=env.str('Port'),
        db_name=env.str('Database'),
        db_user=env.str('User'),
        db_password=env.str('Password'),
        encrypt=env.str('Encrypt'),
        certificate=env.str('TrustServerCertificate'),
        timeout=env.str('ConnectionTimeout')
    )


def get_columns_limit(cursor):
    rows = cursor.execute(
        "select column_name, data_type, character_maximum_length "
        "from information_schema.columns "
        "where table_name = '" + env.str('TableName') + "'"
    )

    columns_list = list()
    for row in rows:
        if row[1] == 'nchar':
            columns_list.append((str(row[0]), int(row[2])))

    return columns_list


def compare_lengths(cursor, values_dict):
    limit_list = get_columns_limit(cursor)

    for col_limit in limit_list:
        if col_limit[0] in values_dict.keys() and col_limit[1] < len(values_dict[col_limit[0]]):
            return {
                'columnName': col_limit[0],
                'columnSize': col_limit[1],
                'actualSize': len(values_dict[col_limit[0]])
            }


def insert_values(cursor, values_dict):
    """Creates an insert command from a template and calls the pyodbc method

     Provided with a dictionary that is structured so the keys match the
     column names and the values are represented by the items that are to be
     inserted the function composes the sql command from a template and
     calls a pyodbc to execute the command.
    """
    insert_command_template = Template(
        'insert into $tableName($columns) values($values)'
    )
    logger.debug('Line to be inserted %s', values_dict)
    values = ''
    table_name = '"' + env.str('TableName') + '"'
    for item in values_dict.values():
        if type(item) == str:
            values = ', '.join([values, "'" + item + "'"])
        else:
            values = ', '.join([values, str(item)])

    insert_command = insert_command_template.substitute(
            tableName=table_name,
            columns=', '.join(values_dict.keys()),
            values=values[1:]
        )

    logger.debug('Insert command that will be exectued:')
    logger.debug(insert_command)

    try:
        cursor.execute(insert_command)
    except pyodbc.DataError as data_error:
        print(dir(data_error))
        if data_error[0] == '22001':
            logger.error('Value to be inserted exceeds column size limit')
            wrong_value = compare_lengths(cursor, values_dict)
            logger.error('Max size for column %s is %i',
                         wrong_value['columnName'], wrong_value['columnSize'])
            logger.error('Actual size for column %s is %i',
                         wrong_value['columnName'], wrong_value['actualSize'])
        else:
            logger.error('Database insertion error', exc_info=True)

        logger.info('Terminating execution')
        sys.exit(0)


def select_row(cursor, row_dict):
    select_cmd_template = Template('select id from $tableName where ($filters)')

    filters = ''

    for col_name, col_value in row_dict.iteritems():
        if type(col_value) == str:
            filters = ' '.join([filters, col_name, '=', "'" + col_value + "'"])
        else:
            filters = ' '.join([filters, col_name, '=', str(col_value)])
        filters = ' '.join([filters, 'AND'])

    table_name = '"' + env.str('TableName') + '"'
    return cursor.execute(
        select_cmd_template.substitute(
            tableName=table_name,
            filters=filters[:-3]
            )
        )


def check_insert(cursor, insertion_list):
    for insert_dict in insertion_list:
        try:
            result = list(select_row(cursor, insert_dict))
            no_rows = len(result)
            if no_rows == 0:
                logger.error("The following line is not pressent in the database: %s" % insert_dict)
            elif no_rows > 1:
                logger.warning("%d identical rows were found" % no_rows)
                logger.warning(result)
            else:
                logger.info("Results inserted successfully to the database")
        except pyodbc.ProgrammingError as pyodbc_error:
            logger.warning("Error while attempting to select row - %s" % pyodbc_error[1])
