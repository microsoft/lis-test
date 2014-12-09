########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

<#
.Synopsis
    Run HammerDB on the target VM.

.Description
    Install HammerDB on the SUT VM, and install MySQL on a server VM.
    Copy modified HammerDB .tcl files into the HammerDB directory.  The
    modified files simulate the user interaction with the HammerDB GUI
    so no user interaction is required.  Configure the root user for autologin
    on the SUT and setup HammerDB to autostart.  Reboot the VM, let HammerDB
    run, then collect the hdb.log file and extract the TPM and NOPM metrics.

    The default values in the perf_hammerdbmysql.sh script were selected to minimize
    the number of test parameters required.  A typical test run would only require
    one test parameter of:
        <param>MYSQL_HOST=IPforMYSQL</param>
    where the IP address is the address of the server to install MySQL on.

    A sample LISA test case definition would look similar to the following:

    <test>
        <testName>HammerDB</name>
        <testScript>setupscripts\Perf_HammerDB.ps1</testScript>
        <files>remote-scripts\ica\perf_hammerdb.sh,tools\lisahdb.tcl,tools\hdb_tpcc.tcl,packages\HammerDB-2.16-Linux-x86-64-Install,packages\MySQL-5.6.16-1.sles11.x86_64.rpm-bundle.tar</files>
        <onError>Continue</onError>
        <timeout>3600</timeout>
        <testParams>
            <param>HAMMERDB_PACKAGE=HammerDB-2.16-Linux-x86-64-Install</param>
            <param>HAMMERDB_URL=http://sourceforge.net/projects/hammerora/files/HammerDB/HammerDB-2.16/</param>
            <param>NEW_HDB_FILE=lisahdb.tcl</param>
            <param>NEW_TPCC_FILE=hdb_tpcc.tcl</param>
            <param>RDBMS=MySQL</param>
            <param>MYSQL_HOST=127.0.0.1</param>
            <param>MYSQL_PORT=3306</param>
            <param>MY_COUNT_WARE=2</param>
            <param>MYSQL_NUM_THREADS=4</param>
            <param>MYSQL_USER=root</param>
            <param>MYSQL_PASS=redhat</param>
            <param>MYSQL_DBASE=tpcc</param>
            <param>MY_TOTAL_ITERATIONS=1000000</param>
            <param>MYSQLDRIVER=timed</param>
            <param>MY_RAMPUP=1</param>
            <param>MY_DURATION=3</param>
            <param>MYSQL_PACKAGE="MySQL-5.6.16-1.sles11.x86_64.rpm-bundle.tar</param>
        </testParams>
    </test>

    Test parameters
        HAMMERDB_PACKAGE
            Name of the HammerDB package to install.
        HAMMERDB_URL
            The URL of where to download HammerDB from.
        NEW_HDB_FILE
            Modified hammerdb.tcl file.
        NEW_TPCC_FILE
            Modified hdb_tpcc.tcl file
        RDBMS
            Name of the database to use.  For this test, it must be MySQL.
        MYSQL_HOST
            IPv4 address of host to install MySQL on.
        MYSQL_PORT
            TCP port the MySQL server is listening on.
        MY_COUNT_WARE
            Number of HammerDB Warehouses to create.
        MYSQL_NUM_THREADS
            Number of HammerDB virtual users to create.
        MYSQL_USER
            The username to use when connecting to the MySQL database.
        MYSQL_PASS
            The password to use when connecting to the MySQL database.
        MYSQL_DBASE
            Which Benchmark to run - this should always be TPCC.
        MY_TOTAL_ITERATIONS
            Number of iterations for a 'Standard" test.
        MYSQLDRIVER
            Type of test - Standard or Timed.
        MY_RAMPUP
            Warm up time in minutes.
        MY_DURATION
            Duration to run the HammerDB test in minutes.
        MYSQL_PACKAGE
            Name of the MySQL package to install on the MYSQL_HOST

.Parameter vmName
    Name of the VM to test.

.Parameter  hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter  testParams
    A string with test parameters.
#>

param ([String] $vmName, [String] $hvServer, [String] $testParams)

# DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG
#$testParams="rootDir=C:\WS2012R2\lisa;ipv4=IP;sshKey=rhel5_id_rsa.ppk;NEW_HDB_FILE=lisahdb.tcl"
# DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG

#####################################################################
#
# ConfigureHammerDbOnSUT()
#
#####################################################################
function ConfigureHammerDbOnSUT()
{
    #
    # Run the Perf_HammerDBMySQL.sh script on the SUT.
    #
    # Installing MySQL will write warnings to STDERR.  This output
    # makes Putty think the command failed.  Because of this,
    # we will look at the contents of the state.txt file
    #
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 ./perf_hammerdbmysql.sh"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ./perf_hammerdbmysql.sh 2> /dev/null"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./perf_hammerdbmysql.sh"

    $state = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat state.txt"
    if ($state -ne "TestCompleted")
    {
        Throw "Error running perf_hammerdbmysql.sh on SUT`n"
    }
}


#####################################################################
#
# RunHammerDbOnSUT()
#
#####################################################################
function RunHammerDbOnSUT()
{
    #
    # Reboot the SUT VM
    #
    # First, stop the VM
    #
    Stop-VM -Name $vmName -ComputerName $hvSErver -Force
    if ($? -ne $True)
    {
        Throw "Error: RunHammerDbOnSUT - Unable to stop VM '${vmName}'"
    }

    $timeout = 300
    $sts = WaitForVMToStop $vmName $hvServer $timeout
    if ($sts -ne $True)
    {
        Throw "Error: RunHammerDbOnSUT - Unable to stop the SUT VM '${vmName}'"
    }

    #
    # Now start the VM
    #
    Start-VM -Name $vmName -ComputerName $hvServer
    if ($? -ne $True)
    {
        Throw "Error: RunHammerDbOnSUT - Unable to start the VM '${vmName}'"
    }

    #
    # Wait for the SSH port to be open on the VM
    #
    $timeout = 300
    $sts = WaitForVMToStartSSH $ipv4 300
    if ($sts -ne $True)
    {
        Throw "Error: RunHammerDbOnSUT - Detecting SSH startup timed out"
    }

    #
    # Verify HammerDB started on the VM
    #
    # Sleep for a bit to give HammerDB a bit more time to start
    #
    Start-Sleep -S 5

    $lc = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ps aux | grep ${newHdbFile} | wc -l"
    if ($lc -lt 2)
    {
        Throw "Error: HammerDB is not running on the SUT after the reboot"
    }
}


#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

#
# Parse the testParams string
#
"Info : Parsing test parameters"
$sshKey = $null
$ipv4 = $null
$rootDir = $null
$tcCovered = "Perf-TPCC"
$newHdbFile = $null
$testLogDir = $null

$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        continue   # Just ignore the parameter
    }
    
    $val = $tokens[1].Trim()
    
    switch($tokens[0].Trim().ToLower())
    {
    "ipv4"          { $ipv4        = $val }
    "sshkey"        { $sshKey      = $val }
    "rootdir"       { $rootDir     = $val }
    "TC_COVERED"    { $tcCovered   = $val }
    "NEW_HDB_FILE"  { $newHdbFile  = $val }
    "TestLogDir"    { $testLogDir  = $val }
    default         { continue }
    }
}

#
# Make sure the required testParams were found
#
"Info : Verify required test parameters were provided"
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

#
# Change the working directory to where we should be
#
if (-not $rootDir){
    "Error: The roodDir test parameter was not provided"
    return $False
}

if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

"Info : Changing directory to ${rootDir}"
cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
"Info : Covers ${tcCovered}" >> $summaryLog

#
# Source the utility functions so we have access to them
#
. .\setupscripts\TCUtils.ps1

#
# Eat any Putty prompts to save the server key
#
echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} exit

try
{
    #
    # Configure HammerDB and MySQL on the target machines
    #
    "Info : Configuring HammerDB and MySQL"
    ConfigureHammerDbOnSut

    #
    # Reboot the SUT so the root user is logged in automatically, and
    # HammerDB is autostarted
    #
    "Info : Rebooting the VM so HammerDB autostarts"
    RunHammerDbOnSut
}
catch
{
    "Error: SUT reported an error:"
    $_.Exception.Message
    $_.Exception.Message >> $summaryLog
    return $False
}

#
# Poll for the creation of the hdb.log file on the SUT,
# then copy the log file to the test log directory.
#
"Info : Waiting for the modified HammerDB to create the hdb.log file"

$increment = 10
$timeout = 3600
while ($timeout -gt 0)
{
    #
    # Try to pull hdb.log from the SUT
    #
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[ -e ~/hdb.log ]"
    if ($? -eq $True)
    {
        break
    }

    Start-Sleep -Seconds $increment
    $timeout -= $increment
}

if ($timeout -le 0)
{
    "Error: Unable to detect hdb.log on ${vmName}"
    "Unable to detect hdb.log" >> $summaryLog
    return $False
}

"Info : Copy hdb.log from the SUT"
bin\pscp.exe -i ssh\${sshKey} root@${ipv4}:hdb.log ${testLogDir}\hdb.log
if ($? -ne $True)
{
    "Error: Unable to copy the HammerDB hbd.log file from the VM"
    "Unable to copy hdb.log from VM" >> $summaryLog
    return $False
}

#
# Display the contents of the hdb.log file so it is captured in the log file
#
cat ${testLogDir}\hdb.log

return $True
