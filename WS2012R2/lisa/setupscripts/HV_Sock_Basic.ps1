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
    This script tests kernel module hv_sock.

.Description

    This test covers basic socket connection and data transmission using
    hv-sock.

    A typical XML definition for this test case would look similar
    to the following:
    <test>
          <testName>HV_Sock_Basic</testName>
          <testScript>setupscripts\HV_Sock_Basic.ps1</testScript>
          <files>tools/hv-sock/server_on_vm.c</files>
          <files>tools/hv-sock/client_on_vm.c</files>
          <testParams>
              <param>TC_COVERED=HV-Sock-01</param>
          </testParams>
          <timeout>400</timeout>
    </test>

.Parameter vmName
    Name of the VM to test.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case.

.Example
    setupScripts\HV_Sock_Basic.ps1 -vmName NameOfVm -hvServer localhost -testParams 'sshKey=path/to/ssh;ipv4=ipaddress'
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False

# Default location for host-end app
$server_on_host_local_path = ".\tools\hv-sock\server_on_host.exe"
$client_on_host_local_path = ".\tools\hv-sock\client_on_host.exe"

# Setup: Create PSSession, connect to remote host
function Create_PSSession{
    $Script:RemoteSession = New-PSSession -ComputerName $hvServer
    if ($? -ne $True){
        Write-Output "Error: Failed to create PSSession!"| Tee-Object -Append -file $summaryLog
        Cleanup_Host
        return $Aborted
    }
    return $True
}

# Setup: Copy host-end app to remote host temp path
#   Files:  server_on_host.exe
#           client_on_host.exe
function Copy_Executables_To_Host{
    # Check local files exist
    if ( -not (Test-Path $server_on_host_local_path) ){
        Write-Output "Error: server_on_host.exe does not exist in tools!"| Tee-Object -Append -file $summaryLog
        Cleanup_Host
        return $Aborted
    }
    if ( -not (Test-Path $client_on_host_local_path) ){
        Write-Output "Error: client_on_host.exe does not exist in tools!"| Tee-Object -Append -file $summaryLog
        Cleanup_Host
        return $Aborted
    }

    # Fetch host temp path
    $server_on_host_remote_path = Invoke-Command -Session $RemoteSession -ScriptBlock{
        $temp_path = [System.IO.Path]::GetTempPath()
        $server_on_host_remote_path = [System.IO.Path]::Combine($temp_path, "server_on_host.exe")
        $server_on_host_remote_path
    }
    $client_on_host_remote_path = Invoke-Command -Session $RemoteSession -ScriptBlock{
        $client_on_host_remote_path = [System.IO.Path]::Combine($temp_path, "client_on_host.exe")
        $client_on_host_remote_path
    }

    # Send files to host
    foreach ( $file_src_dst in @(
        @($server_on_host_local_path, $server_on_host_remote_path),
        @($client_on_host_local_path, $client_on_host_remote_path))
    ){
        Copy-Item $file_src_dst[0] -ToSession $RemoteSession -Destination $file_src_dst[1] -Force

        # Check files successfully sent to remote host
        if (-not $?) {
            Write-Output "[Error] Failed to copy host-end apps to remote host!"| Tee-Object -Append -file $summaryLog
            Cleanup_Host
            return $Aborted
        }
    }
    return $True
}

# Setup: Insert communication service register entry on host
#   Add hv sock service guid into register if it does not exist yet
#   Refernce: https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/make-integration-service
function Insert_Register_Entry{
    Invoke-Command -Session $RemoteSession -ScriptBlock{
        # Host register path
        $RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\GuestCommunicationServices'
        $RegKey = '00000808-facb-11e6-bd58-64006a7986d3'
        $RegPathKey = $RegPath + '\' + $RegKey
        $RegExists = Test-Path $RegPathKey
        if ($RegExists) { return $True }
        else {
            # Add register item
            $service = New-Item -Path $RegPath -Name $RegKey
            $service.SetValue("ElementName", "HV Socket Service")

            # Check item successfully being added
            $RegExists = Test-Path $RegPathKey
            if ($RegExists) { return $True }
            else { return $False }
        }
    }

    if (-not $?) {
        Write-Output "[Error] Failed to add hv-sock service key into host register!"| Tee-Object -Append -file $summaryLog
        Cleanup_Host
        return $Aborted
    }
    return $True
}

# Test Part I: Client app on guest connects server app on host
function Test_Part_I{

    # Start server on host
    $server_process = Invoke-Command -Session $RemoteSession -ScriptBlock{
        $server_process_remote = Start-Process $server_on_host_remote_path -PassThru
    }

    # Start client on vm
    sleep 2 # Make sure server process started before client tries to connect

    # Check if compiled file is on the VM. If it isn't, send it and compile it.
    $checkFile = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[ -e client_on_vm ]; echo `$?"
    if ($checkFile -ne 0) {
        Write-Output "Info: Unable to find client_on_vm. Sending source file for compilation."
        $checkCFile = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[ -e client_on_vm.c ]; echo `$?"
        if ($checkFile -ne 0) {
            SendFileToVM $ipv4 $sshKey ".\tools\hv-sock\client_on_vm.c" "/root/client_on_vm.c"
            if ($? -ne "True") {
                Write-Output "Error: Unable to send client_on_vm.c to $vmName" | Tee-Object -Append -file $summaryLog
                return $Aborted
            }
        }
        .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "gcc client_on_vm.c -o client_on_vm"
        if ($? -ne "True") {
            Write-Output "Error: Unable to compile client_on_vm.c" | Tee-Object -Append -file $summaryLog
            return $Aborted
        }
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 700 client_on_vm"
    $exec = ".\bin\plink.exe"
    $exec_arg = "-i ssh\${sshKey} root@${ipv4} ""./client_on_vm"""
    $client_process = Start-Process $exec -ArgumentList $exec_arg -PassThru

    # Check test result
    Wait-Process -Id $client_process.Id -ErrorAction SilentlyContinue
    # Server should exit with code 0 when client finished connection.
    sleep 2
    $server_exit_code = Invoke-Command -Session $RemoteSession -ScriptBlock{ $server_process_remote.ExitCode }
    $client_exit_code = $client_process.ExitCode

    if (($server_exit_code -eq 0) -and ($client_exit_code -eq 0)) {
        Write-Output "Test host as server passed." | Tee-Object -Append -file $summaryLog
        return $True
    }
    else {
        $errInfo = "Test host as server failed!`n"
        $errInfo += "Server Process Exit Code: $server_exit_code`n"
        $errInfo += "Client Process Exit Code: $client_exit_code`n"
        Write-Output $errInfo | Tee-Object -Append -file $summaryLog
        Cleanup_Host
        return $Failed
    }
}

# Test Part II: Server app on guest connect to client app on host
function Test_Part_II{

    # Check if compiled file is on the VM. If it isn't, send it and compile it.
    $checkFile = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[ -e server_on_vm ]; echo `$?"
    if ($checkFile -ne 0) {
        Write-Output "Info: Unable to find server_on_vm. Sending source file for compilation."
        $checkCFile = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "[ -e server_on_vm.c ]; echo `$?"
        if ($checkFile -ne 0) {
            SendFileToVM $ipv4 $sshKey ".\tools\hv-sock\server_on_vm.c" "/root/server_on_vm.c"
            if ($? -ne "True") {
                Write-Output "Error: Unable to send server_on_vm.c to $vmName" | Tee-Object -Append -file $summaryLog
                return $Aborted
            }
        }
        .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "gcc server_on_vm.c -o server_on_vm"
        if ($? -ne "True") {
            Write-Output "Error: Unable to compile server_on_vm.c" | Tee-Object -Append -file $summaryLog
            return $Aborted
        }
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 700 server_on_vm"
    $exec = ".\bin\plink.exe"
    $exec_arg = "-i ssh\${sshKey} root@${ipv4} ""./server_on_vm"""
    $server_process = Start-Process $exec -ArgumentList $exec_arg -PassThru

    # Start client on host
    sleep 2 # Make sure server process started before client tries to connect
    Invoke-Command -Session $RemoteSession -ScriptBlock{
        $vm_guid = (Get-VM -Name $Using:vmName).Id.ToString()
        $client_process_remote = Start-Process $client_on_host_remote_path -ArgumentList $vm_guid -PassThru
    }

    # Check test result
    Wait-Process -Id $server_process.Id -ErrorAction SilentlyContinue
    sleep 2 # Make sure server process started before client tries to connect
    $server_exit_code = $server_process.ExitCode
    $client_exit_code = Invoke-Command -Session $RemoteSession -ScriptBlock{ $client_process_remote.ExitCode }
    if (($server_exit_code -eq 0) -and ($client_exit_code -eq 0)) {
        Write-Output "Test vm as server passed." | Tee-Object -Append -file $summaryLog
        return $True
    }
    else {
        $errInfo = "Test vm as server failed!`n"
        $errInfo += "Server Process Exit Code: $server_exit_code`n"
        $errInfo += "Client Process Exit Code: $client_exit_code`n"
        Write-Output $errInfo | Tee-Object -Append -file $summaryLog
        Cleanup_Host
        return $Failed
    }
}

# Cleanup function
#   1. Stop host-end apps ( server_on_host.exe, client_on_host.exe )
#   2. Delete host register entry created for this test
#   3. Delete host-end apps ( server_on_host.exe, client_on_host.exe )
#   4. Clean removal of PSSession to remote host
function Cleanup_Host {
    Invoke-Command -ErrorAction SilentlyContinue -Session $RemoteSession -ScriptBlock {
        # Stop host-end apps
        foreach ( $process_name in @("server_on_host", "client_on_host") ){
            $process = Get-Process -Name $process_name -ErrorAction SilentlyContinue
            if ($process -ne $Null) { Stop-Process $process -ErrorAction SilentlyContinue }
        }

        # Delete register key, host-end executable files
        foreach ( $item_name in @(
            $RegPathKey,
            $server_on_host_remote_path,
            $client_on_host_remote_path)
        ){
            Remove-Item $item_name -ErrorAction SilentlyContinue
        }
    }
    Remove-PSSession $RemoteSession -ErrorAction SilentlyContinue
}

# Checking the input arguments
if (-not $vmName) {
    "Error: VM name is null!"
    return $Failed
}

if (-not $hvServer) {
    "Error: hvServer is null!"
    return $Failed
}

if (-not $testParams) {
    "Error: No testParams provided!"
    "This script requires the test case ID and VM details as the test parameters."
    return $Failed
}

#
# Checking the mandatory testParams. New parameters must be validated here.
#
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")

    if ($fields[0].Trim() -eq "TC_COVERED") {
        $TC_COVERED = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TEST_TYPE") {
        $TEST_TYPE = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "rootDir") {
        $rootDir = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "ipv4") {
        $IPv4 = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "sshkey") {
        $sshkey = $fields[1].Trim()
    }
    if ($fields[0].Trim() -eq "TestLogDir") {
        $TestLogDir = $fields[1].Trim()
    }
}

#
# Change the working directory for the log files
# Delete any previous summary.log file, then create a new one
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist"
    return $Failed
}
cd $rootDir

# Source TCUtils.ps1 for test related functions
if (Test-Path ".\setupscripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $Failed
}

# Delete any previous summary.log file, then create a new one
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

# get host build number
$BuildNumber = GetHostBuildNumber $hvServer

if ($BuildNumber -eq 0)
{
    Write-Output "Error: Unable to get Host build number. Aborting test." | Tee-Object -Append -file $summaryLog
    return $Aborted
}

# HV-Socket supported from Windows Server 2016
if ($BuildNumber -lt 14393)
{
    Write-Output "Info: Host does not support hv-sock. Skipping test" | Tee-Object -Append -file $summaryLog
    return $Skipped
}

# Check if VM kernel version supports hv-sock
# Kernel version for RHEL 7.5 (Might need update after 7.5 official release)
$supportkernel = "3.10.0-860"
$kernelSupport = GetVMFeatureSupportStatus $ipv4 $sshKey $supportkernel
if ($kernelSupport -ne "True") {
    Write-Output "Info: Current VM Linux kernel version does not support hv-sock feature." | Tee-Object -Append -file $summaryLog
    return $Skipped
}

################################################
#   Environment Setup
################################################

# Connect to remote host
$ReturnCode = Create_PSSession
if (@($ReturnCode)[-1] -ne $True) {
    Write-Output "Error: Unable to create PSSession. Exit code: $ReturnCode"
    $retVal = $False
}

# Copy host-end app to remote host temp path
$ReturnCode = Copy_Executables_To_Host
if (@($ReturnCode)[-1] -ne $True) {
    Write-Output "Error: Unable to copy executables to host. Exit code: $ReturnCode"
    $retVal = $False
}

# Insert communication service register entry on host
$ReturnCode = Insert_Register_Entry
if (@($ReturnCode)[-1] -ne $True) {
    Write-Output "Error: Unable to insert registry entry. Exit code: $ReturnCode"
    $retVal = $False
}

# Guest linux load hv_sock module
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "modprobe hv_sock"

################################################
#   Main Test
################################################

switch ($TEST_TYPE)
{
    # Test Part I: Client app on guest connects server app on host
    1 { $retVal = Test_Part_I; break }
    # Test Part II: Server app on guest connect to client app on host
    2 { $retVal = Test_Part_II; break }
    default { Write-Output "Error: Wrong scenario specified. Aborting test."; return $Aborted; break}
}

# If we get here it means everything worked
Cleanup_Host
$retVal
