def create_xml_file(file_path):
    with open(file_path, 'w+') as xml_file:
        xml_file.writelines('''<?xml version="1.0" encoding="utf-8"?>
<config>
    <global>
        <logfileRootDir>TestResults</logfileRootDir>
        <defaultSnapshot>ICABase</defaultSnapshot>
    </global>
    <testSuites>
        <suite>
            <suiteName>Network</suiteName>
            <suiteTests>
                <suiteTest>External</suiteTest>
            </suiteTests>
        </suite>
    </testSuites>
    <testCases>
        <test>
            <testName>External</testName>
            <setupScript>setupScript</setupScript>
            <testParams>
                <param>NIC=nicSetup</param>
                <param>TC_COVERED=NET-02</param>
            </testParams>
            <files>path_to_file1,path_to_file2</files>
        </test>
    </testCases>
    <VMs>
        <vm>
            <hvServer>localhost</hvServer>
            <vmName>VMName</vmName>
            <os>Linux</os>
            <ipv4></ipv4>
            <sshKey>sshKey.ppk</sshKey>
            <suite>Network</suite>
        </vm>
    </VMs>
</config>''')


def create_ica_file(file_path):
    with open(file_path, 'w+') as log_file:
        log_file.writelines('''
Test Results Summary
LISA test run on 01/01/2016 21:21:21
XML file: xml_file_path

VM: VMName
    Server :  localhost
    OS :  Microsoft Windows Server 2012


    Test External                  : Success
          Test covers NET-02
          Successfully pinged 8.8.8.8 on synthetic interface eth1
          Failed to ping 192.168.0.1 on synthetic interface eth1 (as expected)
          Failed to ping 10.10.10.5 on synthetic interface eth1 (as expected)
          Successfully pinged 8.8.8.8 on synthetic interface eth2
          Failed to ping 192.168.0.1 on synthetic interface eth2 (as expected)
          Failed to ping 10.10.10.5 on synthetic interface eth2 (as expected)
          Test successful
    Test InternalNetwork           : Failed
          Test covers NET-03
          Successfully assigned 192.168.0.103 (255.255.255.0) to synthetic interface eth1
          Failed to ping 192.168.0.1 on synthetic interface eth1

LIS Version :  4.4.21-64-default


Logs can be found at path_to_logs
''')
