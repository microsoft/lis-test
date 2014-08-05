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
    Verify that VM will not crash after stress reloading hv modules.

.Description
    This script pushes a bash file to the VM, which reloads all the hyper-v modules.
    Runs the script and waits for either a kernel panic or for the it to finish.
    A typical test case definition for this test script would look
    similar to the following: 
    <test>
        <testName>StressReloadModules</testName>
        <setupscript>setupscripts\CORE_EnableIntegrationServices.ps1</setupscript>
        <testScript>setupscripts\CORE_reload_modules.ps1</testScript>
        <timeout>10600</timeout>
        <testParams>
                <param>snapshotname=ICABase</param>
                <param>TC_COVERED=CORE-18</param>
        </testParams>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>
 
.Parameter vmName
    Name of the VM to perform the test with.
    
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
    
.Parameter testParams
    
.Example
    setupScripts\CORE_reload_modules.ps1 -vmName "myVm" -hvServer "localhost" -TestParams "TC_COVERED=CORE-18"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScript = "CORE_StressReloadModules.sh"
$summaryLog  = "${vmName}_summary.log"
$retVal = $False


#########################################################################
#    
#	get state.txt file from VM.
#
########################################################################
function CheckResult()
{
    $retVal = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $attempts       = 250    
     
    Write-Output "Info : pscp -q -i ssh\${sshKey} root@${ipv4}:$stateFile}"
    while ($attempts -ne 0 ){
        bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . 2>&1 | out-null
        $sts = $?

        if ($sts) {
            if (test-path $stateFile){
                $contents = Get-Content -Path $stateFile
                if ($null -ne $contents){
                    if ($contents -eq $TestCompleted) {                    
                        Write-Output "Info: state file contains TestCompleted"              
                        $retVal = $True
                        break                                             
                    }
                    if ($contents -eq $TestAborted) {
                        Write-Output "Info: State file contains TestAborted failed"                                  
                        break
                    }
                }    
                else {
                    Write-Output "Warning: state file is empty!"
                    break
                }
            }
        }
        else {
            Start-Sleep -s 1
            $attempts--
            if ((Get-VMIntegrationService $vmName | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "Lost Communication") {                     
                Write-Output "Error : Lost Communication to vm" | Out-File -Append $summaryLog                  
                break
            }
            if ($attempts -eq 0){                        
                Write-Output "Error : Reached max number of attempts to extract state file" | Out-File -Append $summaryLog         
                break                                               
            }    
        }
		
        if (test-path $stateFile){
            del $stateFile 
        }
    }
	
    if (test-path $stateFile){
        del $stateFile 
    } 
    return $retVal
}


######################################################################
#
#	Helper function to execute command on remote machine.
# 
#######################################################################
function Execute ([string] $command)
{
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} $command
    return $?
}


######################################################################
#
#	Push the remote script to VM.
# 
#######################################################################
function RunTest ()
{
    "./${remoteScript} &> CORE_StressReloadModules.log " | out-file -encoding ASCII -filepath runtest.sh 

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?) {
        Write-Error -Message "Error: Unable to copy runtest.sh to the VM" -ErrorAction SilentlyContinue 
        return $False
    }      

     .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?) {
        Write-Error -Message "Error: Unable to copy ${remoteScript} to the VM" -ErrorAction SilentlyContinue 
        return $False
    }

    $result = Execute("dos2unix ${remoteScript} 2> /dev/null");
    if (-not $result) {
        Write-Error -Message "Error: Unable to run dos2unix on ${remoteScript}" -ErrorAction SilentlyContinue 
        return $False
    }

    $result = Execute("dos2unix runtest.sh 2> /dev/null");
    if (-not $result) {
        Write-Error -Message "Error: Unable to run dos2unix on runtest.sh" -ErrorAction SilentlyContinue 
        return $False
    }
    
    $result = Execute("chmod +x ${remoteScript} 2> /dev/null");
    if (-not $result) {
        Write-Error -Message "Error: Unable to chmod +x ${remoteScript}" -ErrorAction SilentlyContinue 
        return $False
    }
 
    $result = Execute("chmod +x runtest.sh 2> /dev/null");
    if (-not $result) {
        Write-Error -Message "Error: Unable to chmod +x runtest.sh " -ErrorAction SilentlyContinue 
        return $False
    }

    $result = Execute("./runtest.sh");
    if (-not $result) {
        Write-Error -Message "Error: Unable to submit runtest.sh to atd" -ErrorAction SilentlyContinue 
        return $False
    }

    del runtest.sh
    return $True      
}


#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

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
		"sshKey" { $sshKey  = $fields[1].Trim() }
		"ipv4"   { $ipv4    = $fields[1].Trim() }
		"rootdir" { $rootDir = $fields[1].Trim() }
		"TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
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

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
    return $False
}

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

cd $rootDir

#
# Source the TCUtils.ps1 file
#
. .\setupscripts\TCUtils.ps1

$sts = RunTest
if (-not $($sts[-1])) {         
    "Error: Running CORE_StressReloadModules script failed on the VM, exiting test!"  
    return $False 
}

$status = CheckResult 
if (-not $($status[-1])) {
    "Error: Something went wrong during execution of CORE_StressReloadModules script!" 
    return $False    
}
else {
    $results = "Passed"
    $retVal = $True
}

"Info : Test Stress Reload Modules ${results} "

return $retVal