# LISA Persist

An utility for LIS Automation framework that parses the input and output files of a test run and persists the
results in an SQL Server database

## Installation

```bash
$ git clone git@github.com:LIS/lis-test.git
$ cd WS2012R2/lisa/Infrastructure/lisa-parser
$ pip install -r requirements.txt
```

## Usage

### Basic usage

```bash
$ python lisa_parser.py -demo_files/test.xml  demo_files/ica.log
```

### Optional Arguments:

```
-c | --config      Path to .env file that holds values for the database connection - config/.env default
-l | --loglevel Logging level for the script - 2 default 
                Levels: 1 - Warning, 2 - Info, 3 - Debug
-k | --skipkvp  Flag that indicates if the script searches for DistroVersion and KernelVersion from the VM - default True
-p | --perf     Attribute that indicates if a performance test is being run and the path to the test report log
```

### Specify env file

```bash
$ python lisa-parser.py demo_files/test.xml demo_files/ica.log -c path_to_config_file
```

## Documentation

The script is structured in 4 main modules that handle file parsing, interaction with the virtual machine,
database insertion and the general logic behind a test run.

### file_parser.py
The module handles the parsing of the .xml and .log files.
#### XML Parser
The xml parser uses the default xml python library - xml.etree.cElementTree

The default case involves first iterating through the <suiteTests> section in order to
skip commented tests in the next section.

First it iterates the test cases written in the <suiteTests> section
```python
for test in self.root.iter('suiteTest'):
    tests_dict[test.text.lower()] = dict()
```

The parser then saves specific details for each test case by looking in a separate dictionary through
the get_test_details method.

Also from the XML file specific details regarding the VM are saved.
```python
for machine in self.root.iter('vm'):
            vm_dict[machine.find('vmName').text] = {
                'hvServer': machine.find('hvServer').text,
                'os': machine.find('os').text
            }
```

#### Log file parser
The log file is parsed by a different method that saves the parsed field in the tests_dict created previously
by parsing the initial xml config file
First the function goes through the log file looking for the final section called 'Test Results Summary'
Using regex the script looks for specific patterns in each line and saves the values
```python
for line in log_file:
            line = line.strip()
            if re.search("^VM:", line) and len(line.split()) == 2:
                vm_name = line.split()[1]
```


### VirtualMachine
The class handles the main interaction with the virtual machine, providing also a logical representation
for the VM.

The interaction involves constructing and sending powershell commands to a specific virtual machine
It uses the subprocess module in order to run the commands.
```python
 def execute_command(command_arguments):
    ps_command = subprocess.Popen(
        command_arguments,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
```

### TestRun
The main flow of the parsing and insertion process is handled by the TestRun class. It uses 3 main methods
to handle the parsing and updating test run related info (update_from_xml, update_from_ica, update_from_vm):

All the information is handled by a method that formats data in order to be processed by the functions from
the sql_utils module - parse_for_db_insertion()

### sql_utils.py
Database interaction is handled by the pyodbc module, connection variables being saved in the .env file.

The main method, insert_values, expects a dict in which the keys represent the table column names and the values
are the final values to be inserted
```python
def insert_values(cursor, table_name, values_dict):
    insert_command = Template('insert into $tableName($columns)'
                              ' values($values)')

    cursor.execute(insert_command.substitute(
        tableName=table_name,
        columns=', '.join(values_dict.keys()),
        values=', '.join("'" + item + "'" for item in values_dict.values())
    ))

```

## License
Copyright (c) Cloudbase Solutions 2016
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
