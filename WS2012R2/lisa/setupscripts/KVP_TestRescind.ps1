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
    Verify the KVP service and KVP daemon.

.Description
    Ensure the Data Exchange service is operational after a cycle
    of disable and reenable of the service. Additionally, check that
    the daemon is running on the VM.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>KVP_TestRescind</testName>
            <testScript>SetupScripts\KVP_TestRescind.ps1</testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
            <testparams>
                <param>TC_COVERED=KVP-11</param>
                <param>CycleCount=20</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to test the KVP service on.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case, where CycleCount is the number of cycles of disable and reenable of the KVP service
.Example
    setupScripts\KVP_TestRescind.ps1 -vmName "myVm" -hvServer "localhost -TestParams "rootDir=c:\lisa;TC_COVERED=KVP-11"
.Link
    None.
#>

param([String] $vmName, [String] $hvServer, [String] $testParams)

function Check-Systemd()
{
    $check1 = $true
    $check2 = $true
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls -l /sbin/init | grep systemd"
    if ($? -ne "True"){
        Write-Output "Systemd not found on VM"
        $check1 = $false
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemd-analyze --help"
    if ($? -ne "True"){
        Write-Output "Systemd-analyze not present on VM."
        $check2 = $false
    }

    if (($check1 -and $check2) -eq $true) {
        return $true
    } else {
        return $false
    }
}

#######################################################################
#
# Main script body
#
#######################################################################
#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    Write-Output "Error: no VMName was specified"
    return $Failed
}

if (-not $hvServer)
{
    Write-Output "Error: No hvServer was specified"
    return $Failed
}

if (-not $testParams)
{
    Write-Output "Error: No test parameters specified"
    return $Failed
}
#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue

#
# Parse the test parameters
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "ipv4"      { $ipv4    = $fields[1].Trim() }
    "sshKey"    { $sshKey  = $fields[1].Trim() }
    "rootdir"      { $rootDir   = $fields[1].Trim() }
    "TC_COVERED"   { $tcCovered = $fields[1].Trim() }
    "CycleCount"    { $CycleCount = $fields[1].Trim() }
    default  {}       
    }
}

if (-not $rootDir)
{
    Write-Output "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

echo "Covers: ${tcCovered}" >> $summaryLog

# Source TCUtils.ps1 for common functions
if (Test-Path ".\setupScripts\TCUtils.ps1") {
    . .\setupScripts\TCUtils.ps1
    "Info: Sourced TCUtils.ps1"
}
else {
    "Error: Could not find setupScripts\TCUtils.ps1"
    return $Failed
}

$checkVM = Check-Systemd
if ($checkVM -eq "True") {
    # Get KVP Service status
    $gsi = Get-VMIntegrationService -Name "Key-Value Pair Exchange" -vmName $vmName -ComputerName $hvServer
    if ($? -ne "True") {
        Write-Output "Error: Unable to get Key-Value Pair status on $vmName ($hvServer)" | Tee-Object -Append -file $summaryLog
        return $Failed
    }

    # Check if VM is RedHat 7.2 or older and if it uses external LIS
    # Do a check first for 4.x.x kernel series so that we don't skip it
    $majorKernelVersion = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "uname -r | cut -d. -f1"
    $isRHEL = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "yum --version"
    if ($? -eq "True" -and $majorKernelVersion -lt 4) {
        # If distro is RedHat check the kernel version
        $rhel_kernel = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "uname -r | cut -d. -f3 | cut -d- -f2"
        if ($rhel_kernel -le 327) {
            # If RedHat distro and older kernel, check if LIS-4.x drivers are present
            Write-Output "Info: Kernels older than 3.10.0-514 require LIS-4.x drivers." | Tee-Object -Append -file $summaryLog
            $checkExternal = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rpm -qa | grep kmod-microsoft-hyper-v && rpm -qa | grep microsoft-hyper-v"
            if ($? -ne "True") {
                Write-Output "Error: No LIS-4.x drivers detected. Skipping test." | Tee-Object -Append -file $summaryLog
                return $Skipped
            }
        }
    }

    # If KVP is not enabled, enable it
    if ($gsi.Enabled -ne "True") {
        Enable-VMIntegrationService -Name "Key-Value Pair Exchange" -vmName $vmName -ComputerName $hvServer
        if ($? -ne "True") {
            Write-Output "Error: Unable to enable Key-Value Pair on $vmName ($hvServer)" | Tee-Object -Append -file $summaryLog
            return $Failed
        }
    }

    # Disable and Enable KVP according to the given parameter
        $counter = 0
        while ($counter -lt $CycleCount) {
            Disable-VMIntegrationService -Name "Key-Value Pair Exchange" -vmName $vmName -ComputerName $hvServer
            if ($? -ne "True") {
                Write-Output "Error: Unable to disable VMIntegrationService on $vmName ($hvServer) on $counter run" | Tee-Object -Append -file $summaryLog
                return $Failed
            }
            Start-Sleep 5

            Enable-VMIntegrationService -Name "Key-Value Pair Exchange" -vmName $vmName -ComputerName $hvServer
            if ($? -ne "True") {
                Write-Output "Error: Unable to enable VMIntegrationService on $vmName ($hvServer) on $counter run" | Tee-Object -Append -file $summaryLog
                return $Failed
            }
            Start-Sleep 5
            $counter += 1
        }

        Write-Output "Disabled and Enabled KVP Exchange $counter times" | Tee-Object -Append -file $summaryLog

    #Check KVP service status after disable/enable
    $gsi = Get-VMIntegrationService -Name "Key-Value Pair Exchange" -vmName $vmName -ComputerName $hvServer
    if ($gsi.PrimaryOperationalStatus -ne "OK") {
        Write-Output "Error: Key-Value Pair service is not operational after disable/enable cycle. `
        Current status: $gsi.PrimaryOperationalStatus" | Tee-Object -Append -file $summaryLog
        return $Failed
    } else {
        # Daemon name might vary. Get the correct daemon name based on systemctl output
        $daemonName = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl list-unit-files | grep kvp"
        $daemonName = $daemonName.Split(".")[0]

        #If the KVP service is OK, check the KVP daemon on the VM
        $checkProcess = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "systemctl is-active $daemonName"
        if ($checkProcess -ne "active") {
             Write-Output "Error: $daemonName is not running on $vmName after disable/enable cycle" | Tee-Object -Append -file $summaryLog
             return $Failed
        } else {
            Write-Output "Info: KVP service and $daemonName are operational after disable/enable cycle" | Tee-Object -Append -file $summaryLog
            return $Passed
        }
    }
} else {
    Write-Output "Systemd is not being used. Test Skipped" | Tee-Object -Append -file $summaryLog
    return $Skipped
}
