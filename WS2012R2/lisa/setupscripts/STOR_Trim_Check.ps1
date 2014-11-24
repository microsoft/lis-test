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
    Verify TRIM support.
.Description
    This is a PowerShell test case script that implements TRIM
    support verification when vhdx is stored on a SSD.
    Ensures that after reusing disk space you should see the vhdx size
    grow only by a small amount.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>Trim</testName>
            <testScript>SetupScripts\STOR_Trim_Check.ps1</testScript>
            <files>remote-scripts/ica/STOR_trim.sh</files>
            <setupScript>SetupScripts\Add-VHDXHardDiskWithLocation.ps1</setupScript>
            <timeout>18000</timeout>
            <testparams>
                <param>SCSI=0,0,Dynamic,512,10GB,H:\Virtual Hard Disks\ssd\</param>
                <param>TC_COVERED=STOR-XX</param>
            </testparams>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>
.Parameter vmName
    Name of the VM to test.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    setupScripts\STOR_Trim_Check.ps1 -vmName "VM_Name" -hvServer "HYPERV_SERVER" -TestParams "ipv4=255.255.255.255;sshKey=YOUR_KEY.ppk;SCSI=0,0,Dynamic,512,10GB,H:\Virtual Hard Disks\ssd\;TC_COVERED=STOR-XX"
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

$sshKey     = $null
$ipv4       = $null
$SCSI    = $null
$rootDir    = $null
$TC_COVERED = $null
$TestLogDir = $null
$TestName   = $null


function RunTest([String] $filename)
{

    "exec ./${filename}.sh &> ${filename}.log " | out-file -encoding ASCII -filepath runtest.sh

    .\bin\pscp.exe -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to copy runtest.sh to the VM" -ErrorAction SilentlyContinue
       return $False
    }

     .\.\bin\pscp.exe -i ssh\${sshKey} .\remote-scripts\ica\${filename}.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to copy ${filename}.sh to the VM" -ErrorAction SilentlyContinue
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${filename}.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run dos2unix on ${filename}.sh" -ErrorAction SilentlyContinue
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "sed -i 's,\\,\\\\,g' constants.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run sed on constants.sh" -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run dos2unix on runtest.sh" -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${filename}.sh   2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to chmod +x ${filename}.sh" -ErrorAction SilentlyContinue
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to chmod +x runtest.sh " -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh 2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run runtest.sh " -ErrorAction SilentlyContinue
        return $False
    }

    del runtest.sh
    return $True
}

#########################################################################
#    get state.txt file from VM.
########################################################################
function CheckResult()
{
    $retVal = $False
    $stateFile     = "state.txt"
    $localStateFile= "${vmName}_state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000

    "Info :   pscp -q -i ssh\${sshKey} root@${ipv4}:$stateFile} ."
    while ($timeout -ne 0 )
    {
    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${stateFile} ${localStateFile} #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $localStateFile)
        {
            $contents = Get-Content -Path $localStateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {
                        # Write-Host "Info : state file contains Testcompleted"
                        $retVal = $True
                        break

                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Host "Info : State file contains TestAborted failed. "
                         break

                    }

                    $timeout--

                    if ($timeout -eq 0)
                    {
                        Write-Error -Message "Error : Timed out on Test Running , Exiting test execution."   -ErrorAction SilentlyContinue
                        break
                    }

            }
            else
            {
                Write-Host "Warn : state file is empty"
                break
            }

        }
        else
        {
             Write-Host "Warn : ssh reported success, but state file was not copied"
             break
        }
    }
    else #
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull state.txt from VM." -ErrorAction SilentlyContinue
         break
    }
    }
    del $localStateFile
    return $retVal
}

#########################################################################
#    get summary.log file from VM.
########################################################################
function SummaryLog()
{
    $retVal = $False
    $summaryFile   = "summary.log"
    $localVMSummaryLog = "${vmName}_error_summary.log"

    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${summaryFile} ${localVMSummaryLog} #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $localVMSummaryLog)
        {
            $contents = Get-Content -Path $localVMSummaryLog
            if ($null -ne $contents)
            {
                   Write-Output "Error: ${contents}" | Tee-Object -Append -file $summaryLog
            }
            $retVal = $True
        }
        else
        {
             Write-Host "Warn : ssh reported success, but summary file was not copied"
        }
    }
    else #
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull summary.log from VM." -ErrorAction SilentlyContinue
    }
     del $summaryFile
     return $retVal
}

#########################################################################
#    get runtest.log file from VM.
########################################################################
function RunTestLog([String] $filename, [String] $logDir, [String] $TestName)
{
    $retVal = $False
    $RunTestFile   = "${filename}.log"

    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${RunTestFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $RunTestFile)
        {
            $contents = Get-Content -Path $RunTestFile
            if ($null -ne $contents)
            {
                    move "${RunTestFile}" "${logDir}\${TestName}_${filename}_vm.log"

                   #Get-Content -Path $RunTestFile >> {$TestLogDir}\*_ps.log
                   $retVal = $True

            }
            else
            {
                Write-Host "Warn : RunTestFile is empty"
            }
        }
        else
        {
             Write-Host "Warn : ssh reported success, but RunTestFile file was not copied"
        }
    }
    else
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull RunTestFile from VM." -ErrorAction SilentlyContinue
         return $False
    }

     return $retVal
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
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
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
$params = $testParams.TrimEnd(";").Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey  = $fields[1].Trim() }
    "ipv4"      { $ipv4    = $fields[1].Trim() }
    "SCSI"       { $SCSI = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Make sure the VM has a SCSI controller, and that
# Lun on the controller has a .vhdx file attached.
#
 $diskArgs = $SCSI.Trim().Split(',')

$controllerID = $diskArgs[0].Trim()
$lun = $diskArgs[1].Trim()

"Info : Get the VM ${vmName} freshly attached disk."
$scsi = Get-VMHardDiskDrive -VMName $vmName -Controllertype SCSI -ControllerNumber $controllerID -ControllerLocation $lun -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $scsi)
{
    "Error: VM ${vmName} does not seem to have the new disk attached."
    $error[0].Exception.Message
    return $False
}

$vhdPath = $scsi.Path

"Info : Verify the file is a .vhdx"
if (-not $vhdPath.EndsWith(".vhdx") -and -not $vhdPath.EndsWith(".avhdx"))
{
    "Error: Virtual disk is not a .vhdx file."
    "       Path = ${vhdPath}"
    return $False
}

#
# Format the disk inside the VM
#
$guest_script = "STOR_trim"

$sts = RunTest $guest_script
if (-not $($sts[-1]))
{
    $sts = SummaryLog
    if (-not $($sts[-1]))
    {
        "Warning : Failed getting summary.log from VM"
    }
    "Error: Running '${guest_script}' script failed on VM "
    return $False
}

$CheckResultsts = CheckResult

$sts = RunTestLog $guest_script $TestLogDir $TestName
if (-not $($sts[-1]))
{
    "Warning : Getting RunTestLog.log from VM, will not exit test case execution "
}

if (-not $($CheckResultsts[-1]))
{
    "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
    return $False
}


if (Test-Path $vhdPath)
{
    $initial_size = (Get-Item $vhdPath).length
}

#
# Recreate a large file
#
"Info : Recreate a 1GB test file on disk"

.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rm /mnt/file.txt 2> /dev/null; sleep 10 "
if (-not $?)
{
    "Error: Failed to delete existing file from disk." | Tee-Object -Append -file $summaryLog
    return $False
}
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "fstrim /mnt 2> /dev/null; sleep 20"
if (-not $?)
{
    "Error: Failed to run fstrim on disk"  | Tee-Object -Append -file $summaryLog
    return $False
}
.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dd if=/dev/urandom of=/mnt/file.txt bs=1024 count=1M 2> /dev/null;"
if (-not $?)
{
    "Error: Failed to recreate 1GB test file on disk"  | Tee-Object -Append -file $summaryLog
    return $False
}

"Info : Get updated disk size"
$final_size = (Get-Item $vhdPath).length
if (-not $?)
{
   "Error: Unable to get  VHDX file '${vhdPath} size"  | Tee-Object -Append -file $summaryLog
   return $False
}

$difference = $final_size - $initial_size
$value = [System.Math]::Round($($difference/(1024*1024)), 2)

if ($difference -gt 300MB)
{
    "Error: Disk size increased by {$value} MB"  | Tee-Object -Append -file $summaryLog
    return $False
}
else
{
    "Success: Disk size increased by $value MB"  | Tee-Object -Append -file $summaryLog
}
return $True