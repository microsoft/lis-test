#####################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#####################################################################


<#
.Synopsis
    Verify the kernel upgrade/downgrade on RHEL guest.
.Description
    Ensure the kernel upgrade/downgrade successfully on RHEL VM.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>redhat_update_kernel</testName>
            <testScript>setupscripts\kernel.ps1</testScript>
            <files>remote-scripts\ica\redhat_upgrade_kernel.sh,remote-scripts\ica\redhat_downgrade_kernel.sh,remote-scripts\ica\utils.sh</files>
            <testParams>
                <param>URL=http://PATH/TO/TEST/KERNEL</param>
                <param>DOWNKERNEL=kernel-3.10.0-305.el7.x86_64.rpm</param>
                <param>UPKERNEL=kernel-abi-whitelists-3.10.0-364.el7.noarch.rpm,kernel-3.10.0-364.el7.x86_64.rpm</param>
                <param>TC_COVERED=KERNEL-01</param>
            </testParams>
            <timeout>900</timeout>
            <OnError>Continue</OnError>
        </test>
.Parameter vmName
    Name of the VM to read intrinsic data from.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Parameter of URL
    The address to download kernel
.Parameter of DOWNKERNEL
    The kernel to downgrade
.Paramter of UPKERNEL
    The kernel of upgrade
.Example
    setupScripts\KvpBasic.ps1 -vmName "myVm" -hvServer "localhost -TestParams "rootDir=c:\lisa\trunk\lisa;URL=http://../pub/kernel/;DOWNKERNEL=kernel-3.10.0-305.el7.x86_64.rpm;UPKERNEL=kernel-abi-whitelists-3.10.0-364.el7.noarch.rpm,kernel-3.10.0-364.el7.x86_64.rpm;TC_COVERED=KERNEL-01;"
.Link

    None.
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

function CheckResults(){
    #
    # Checking test results
    #
    $stateFile = "state.txt"

    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} .

    if ($?) {
        if (test-path $stateFile){
            $contents = Get-Content $stateFile
            if ($null -ne $contents){
                if ($contents.Contains('TestCompleted') -eq $True) {                    
                    Write-Output "Info: Test ended successfully"
                    $retVal = $True
                }
                if ($contents.Contains('TestAborted') -eq $True) {
                    Write-Output "Info: State file contains TestAborted failed"
                    $retVal = $False                           
                }
                if ($contents.Contains('TestFailed') -eq $True) {
                    Write-Output "Info: State file contains TestFailed failed"
                    $retVal = $False                           
                }
            }    
            else {
                Write-Output "ERROR: state file is empty!"
                $retVal = $False    
            }
        }
        
    }
    return $retval
}

#
# MAIN SCRIPT
#
$retVal = $false
$sshKey = $null
$ipv4 = $null
$UpKernel = $null
$DownKernel = $null

#
# Check input arguments
#
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
}

$params = $testParams.Split(";")

foreach ($p in $params) {
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim()) {
        "rootDir"   { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   {$ipv4 = $fields[1].Trim()}
        "TestLogDir" {$logdir = $fields[1].Trim()}
        "UpKernel" {$UpKernel = $fields[1].Trim()}
        "DownKernel" {$DownKernel = $fields[1].Trim()}
        default  {}
    }
}

if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $False
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}
$kernelupArgs = $UpKernel.Trim().Split(',')
$kernelUpVersion = $kernelupArgs[1].Trim()

$kernelDownArgs = $DownKernel.Trim().Split(',')
$kernelDownVersion = $kernelDownArgs[0].Trim()

# Source TCUitls.ps1 for getipv4 and other functions
if (Test-Path ".\setupScripts\TCUtils.ps1")
{
    . .\setupScripts\TCUtils.ps1
}
else
{
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $false
}


$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix redhat_upgrade_kernel.sh && chmod u+x redhat_upgrade_kernel.sh && ./redhat_upgrade_kernel.sh"

#
# Rebooting the VM in order to change new kernel
#
$retVal = SendCommandToVM $ipv4 $sshKey "reboot"
Write-Output "Rebooting the VM."


#
# Waiting the VM to start up
#
Write-Output "Waiting the VM to have a connection..."
do {
    sleep 5
} until(Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )

$kernelPackage =  echo y | bin\plink -i ssh\${sshKey} root@${ipv4} "uname -r"
if (not $kernelUpVersion -match $kernelPackage)
{
    Write-Output "The Kernel version have some problem"
    return $False
} 


bin\pscp -q -i ssh\${sshKey} root@${ipv4}:summary.log $logdir
$retVal = CheckResults $sshKey $ipv4
if (-not $retVal)
{
    "ERROR: Upgrade Results are not as expected(configuration problems). Test Aborted."
    return $false
}

#
# Waiting the VM to have a connection
#
Write-Output "Checking the VM connection after kernel downupgrade..."
$retVal = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix redhat_downgrade_kernel.sh && chmod u+x redhat_downgrade_kernel.sh && ./redhat_downgrade_kernel.sh"

#
# Rebooting the VM in order to change new kernel
#
$retVal = SendCommandToVM $ipv4 $sshKey "reboot"
Write-Output "Rebooting the VM."
#
# Waiting the VM to start up
#
Write-Output "Waiting the VM to have a connection..."

do {
    sleep 5
} until(Test-NetConnection $ipv4 -Port 22 -WarningAction SilentlyContinue | ? { $_.TcpTestSucceeded } )

$kernelPackage =  echo y | bin\plink -i ssh\${sshKey} root@${ipv4} "uname -r"
if (not $kernelDownVersion -match $kernelPackage)
{
    Write-Output "The Kernel version have some problem"
    return $False
}

$retVal = CheckResults $sshKey $ipv4
if (-not $retVal)
{
    "ERROR: Downgrade Results are not as expected(configuration problems). Test Aborted."
    return $false
}
return $retVal
