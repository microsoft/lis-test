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
    Disable then enable the shutdown service and verify shutdown still works.

.Description
    Disable, then re-enable the LIS Shutdown service.  Then verify that
    a shutdown request still works.  The XML test case definition for
    this test would look similar to:
        <test>
            <testName>VerifyItegratedShutdownService</testName>
            <testScript>setupscripts\INST_LIS_ShutdownServiceDisableEnable.ps1</testScript>
            <timeout>600</timeout>
            <testParams>
                <param>TC_COVERED=CORE-16</param>
                <param>rootDir=D:\lisa\trunk\lisablue</param>
            </testParams>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example
    .\INST_LIS_ShutdownServiceDisableEnable.ps1 "myVM" "localhost" "rootDir=D:\lisa\trunk\lisablue;TC_COVERED=10"
#>



param([String] $vmName, [String] $hvServer, [String] $testParams)


#####################################################################
#
# CheckVMState()
#
#####################################################################
function CheckVMState([String] $vmName, [String] $newState)
{
    $stateChanged = $False
    
    $vm = Get-VM $vmName -ComputerName $hvServer    
    if ($($vm.State.ToString()) -eq $newState)
    {
        $stateChanged = $True
    }
    
    return $stateChanged
}


#####################################################################
#
# TestPort
#
#####################################################################
#function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
#{
#    $retVal = $False
#    $timeout = $to * 1000
#
    #
    # Try an async connect to the specified machine/port
    #
#    $tcpclient = new-Object system.Net.Sockets.TcpClient
#    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
#    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    #
    # Check to see if the connection is done
    #
#    if($connected)
#    {
        #
        # Close our connection
        #
#        try
#        {
#            $sts = $tcpclient.EndConnect($iar) | out-Null
#            $retVal = $true
#        }
#        catch
#        {
            # Nothing we need to do...
#        }
#    }
#    $tcpclient.Close()

#    return $retVal
#}


#######################################################################
#
# Main script body
#
#######################################################################

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

if ($testParams -eq $null)
{
    "Error: testParams is null"
    return $False
}

#
# Parse the testParams string
#
$rootDir = $null
$tcCovered = "Undefined"
$ipv4 = $null

"Parsing testParams"
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "ipv4"       { $ipv4      = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    "TC_COVERED" { $tcCovered = $fields[1].Trim() }
    default  {}       
    }
}

if (-not $ipv4)
{
    "Error: This test requires an ipv4 test parameter"
    return $False
}

if (-not $rootDir)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

if (-not (Test-Path $rootDir) )
{
    "Error: The test root directory '${rootDir}' does not exist"
    return $False
}

#
# Display the test parameters so they are captured in the log
#
"IPv4      = ${ipv4}"
"rootDir   = ${rootDir}"
"tcCovered = ${tcCovered}"

#
# PowerShell test case scripts are run as a PowerShell job.  The
# default directory for a PowerShell job is not the LISA directory.
# Change the current directory to where we need to be.
#
cd $rootDir

. .\setupscripts\TCUtils.ps1

#
# Updating the summary log with Testcase ID details
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File $summaryLog

#
# Get the VMs Integrated Services and verify Shutdown is enabled and status is OK
#
"Info : Verify the Integrated Services Shutdown Service is enabled"
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name Shutdown
if ($status.Enabled -ne $True)
{
    "Error: The Itegrated Shutdown Service is already disabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Shutdown Service: $($status.PrimaryOperationalStatus)"
    return $False
}

#
# Disable the Shutdown service.
#
"Info : Disabling the Integrated Services Shutdown Service"

Disable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name Shutdown
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name Shutdown
if ($status.Enabled -ne $False)
{
    "Error: The Shutdown Service could not be disabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Shutdown Service: $($status.PrimaryOperationalStatus)"
    return $False
}
"Info : Integrated Shutdown Service successfully disabled"

#
# Enable the Shutdown service
#
"Info : Enabling the Integrated Services Shutdown Service"

Enable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name Shutdown
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name Shutdown
if ($status.Enabled -ne $True)
{
    "Error: Integrated Shutdown Service could not be enabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Shutdown Service: $($status.PrimaryOperationalStatus)"
    return $False
}
"Info : Integrated Shutdown Service successfully Enabled"

#
# Now do a shutdown to ensure the Shutdown Service is still functioning
#
"Info : Shutting down the VM"

$ShutdownTimeout = 600
Stop-VM -Name $vmName -ComputerName $hvServer -Force
while ($shutdownTimeout -gt 0)
{
    if ( (CheckVMState $vmName "Off"))
    {
        break
    }   

    Start-Sleep -seconds 2
    $shutdownTimeout -= 2
}

if ($shutdownTimeout -eq 0)
{
    "Error: Shutdown timed out waiting for VM to go to Off state"
    return $False
}

"Info : VM ${vmName} Shutdown successful"

#
# Now start the VM so the automation scripts can do what they need to do
#
"Info : Starting the VM"

Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$false
if ($? -ne "True")
{
    "Error: Unable to restart the VM"
    return $False
}

$startTimeout = 300
if (-not (WaitForVMToStartSSH $ipv4 $StartTimeout))
{
    "Error: VM did not start within timeout period"
    return $False
}

"VM successfully started"

#
# If we reached here, everything worked fine
#
return $True
