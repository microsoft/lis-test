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
 Enable and configure Dynamic Memory for given Virtual Machines and look for Hot-Add udev rule presence.

 Description:
    Enable & configure Dynamic Memory parameters for a set of Virtual Machines.
    
    vmName - name of a existing virtual machine.

    rootdir - folder where lisa is located.
    
    TestLogDir (optional) - a path for saving remote logs.

    sshKey is the path to the ssh key for accesing the vm
    
    ipv4 is the ip of the vm
    
    The memory testparams have to be formated like this:    
    minMem= (decimal) [MB|GB|%], maxMem=(decimal) [MB|GB|%], 
    startupMem=(decimal) [MB|GB|%], memWeight=(0 < decimal < 100) 
    
    minMem - the minimum amount of memory assigned to the specified virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host

    maxMem - the maximum memory amount assigned to the virtual machine(s)
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host
      
    startupMem - the amount of memory assigned at startup for the given VM
    the amount of memory can be specified as a decimal followed by a qualifier
    valid qualifiers are: MB, GB and % . %(percent) means percentage of free Memory on the host

    memWeight - the priority a given VM has when assigning Dynamic Memory
    the memory weight is a decimal between 0 and 100, 0 meaning lowest priority and 100 highest.

    The following is an example of a testParam for configuring Dynamic Memory

       "rootdir=C:\lis-test\WS2012R2\lisa;sshKey=rhel5_id_rsa.ppk;ipv4=10.7.1.217;minMem=512MB;maxMem=50%;startupMem=1GB;memWeight=20"

    All setup and cleanup scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.
   
    .Parameter vmName
    Name of the VM to remove NIC from .

    .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

    .Parameter testParams
    Test data for this test case

    .Example
    setupScripts\DM_HotAdd_Verify_udev -vmName Ubuntu14.10 -hvServer localhost -testParams "rootdir=C:\lis-test\WS2012R2\lisa;sshKey=rhel5_id_rsa.ppk;ipv4=10.7.1.217;minMem=512MB;maxMem=50%;startupMem=1GB;memWeight=20"
#>

param([string] ${vmName}, [string] $hvServer, [string] $testParams)

#######################################################################
# Runs a remote script on the VM an returns the log.
#######################################################################
function RunRemoteScript($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000    

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh 

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }      

     .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh" 
        return $False
    }
    
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}" 
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh"

    # Return the state file
    while ($timeout -ne 0 )
    {
    .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $stateFile)
        {
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {                    
                        Write-Output "INFO: state file contains TestCompleted."
                        $retValue = $True
                        break
                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Output "INFO: State file contains TestAborted."
                         break
                          
                    }
                    #Start-Sleep -s 1
                    $timeout-- 

                    if ($timeout -eq 0)
                    {                        
                        Write-Output "ERROR: Timed out on test run, exiting."
                        break
                    }

            }
            else
            {
                Write-Output "WARN: State file is empty."
                break
            }
           
        }
        else
        {
             Write-Host "WARN: ssh reported success, but state file was not copied!"
             break
        }
    }
    else #
    {
         Write-Output "ERROR: pscp exit status = $sts"
         Write-Output "ERROR: Unable to pull state.txt from VM!" 
         break
    }
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"
    
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} . 
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"
                
                    }

                    else 
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"
                    }
                  
            }    
            else
            {
                Write-Output "WARN: $remoteScriptLog is empty"
            }
        }
        else
        {
             Write-Output "WARN: ssh reported success, but $remoteScriptLog file was not copied"
        }
    }
    
    # Cleanup 
    del state.txt -ERRORAction "SilentlyContinue"
    del runtest.sh -ERRORAction "SilentlyContinue"

    return $retValue
}

#######################################################################
# Convert a string to int64 for use with the Set-VMMemory cmdlet
#######################################################################
function ConvertToMemSize([String] $memString, [String]$hvServer)
{
    $memSize = [Int64] 0

    if ($memString.EndsWith("MB"))
    {
        $num = $memString.Replace("MB","")
        $memSize = ([Convert]::ToInt64($num)) * 1MB
    }
    elseif ($memString.EndsWith("GB"))
    {
        $num = $memString.Replace("GB","")
        $memSize = ([Convert]::ToInt64($num)) * 1GB
    }
    elseif( $memString.EndsWith("%"))
    {
        $osInfo = Get-WMIObject Win32_OperatingSystem -ComputerName $hvServer
        if (-not $osInfo)
        {
            "ERROR: Unable to retrieve Win32_OperatingSystem object for server ${hvServer}"
            return $False
        }

        $hostMemCapacity = $osInfo.FreePhysicalMemory * 1KB
        $memPercent = [Convert]::ToDouble("0." + $memString.Replace("%",""))
        $num = [Int64] ($memPercent * $hostMemCapacity)

        # Align on a 4k boundry
        $memSize = [Int64](([Int64] ($num / 2MB)) * 2MB)
    }
    # we received the number of bytes
    else
    {
        $memSize = ([Convert]::ToInt64($memString))
    }

    return $memSize
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################
$retVal = $false
$remoteScript = "DM_HotAdd_Verify_udev.sh"
$DMenabled = $true

# Define and cleanup the summaryLog
$summaryLog  = "${vmName}_summary.log"
echo "Covers DM Hot-Add" > $summaryLog


# Check input arguments
if (-not ${vmName})
{
    Write-Output "ERROR: vmName is null. "
    return $false
}
else
{
    Write-Output "vmName: ${vmName}"
}

if (-not $hvServer)
{
    Write-Output "ERROR: hvServer is null"
    return $false
}
else
{
    Write-Output "hvServer: $hvServer"
}

if (-not $testParams)
{
    Write-Output"ERROR: testParams is null"
    return $false
}

# Extracting testparams
$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
        switch ($fields[0].Trim())
        {
        "sshKey" { $sshKey = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "rootdir" { $rootDir = $fields[1].Trim() }
        "TestLogDir" { $TestLogDir = $fields[1].Trim() }
        "minMem" { $minMem = $fields[1].Trim() }
        "maxMem" { $maxMem = $fields[1].Trim() }
        "startupMem" { $startupMem = $fields[1].Trim() }
        "memWeight" { $memWeight = $fields[1].Trim() }
        default  {}          
        }
}

if ($null -eq $sshKey)
{
    Write-Output "ERROR: Test parameter sshKey was not specified"
    return $False
}
else
{
    Write-Output "sshKey: $sshKey"
}

if ($null -eq $ipv4)
{
    Write-Output "ERROR: Test parameter ipv4 was not specified"
    return $False
}
else
{
    Write-Output "ipv4: $ipv4"
}

if ($null -eq $rootdir)
{
    Write-Output "ERROR: Test parameter rootdir was not specified"
    return $False
}
else
{
    Write-Output "rootdir: $rootdir"
}

if ($null -eq $minMem)
{
    Write-Output "ERROR: Test parameter minMem was not specified"
    return $False
}
else 
{
    $minMem = ConvertToMemSize $minMem $hvServer
    if ($minMem -le 0)
    {
        Write-Output "ERROR: Unable to convert minMem to int64."
        return $false
    }
    Write-Output "minMem: $minMem"
}

if ($null -eq $maxMem)
{
    Write-Output "ERROR: Test parameter maxMem was not specified"
    return $False
}
else 
{
    $maxMem = ConvertToMemSize $maxMem $hvServer
    if ($maxMem -le 0)
    {
        Write-Output "ERROR: Unable to convert maxMem to int64."
        return $false
    }
    Write-Output "maxMem: $maxMem"
}

if ($null -eq $startupMem)
{
    Write-Output "ERROR: Test parameter startupMem was not specified"
    return $False
}
else 
{
    $startupMem = ConvertToMemSize $startupMem $hvServer
    if ($startupMem -le 0)
    {
        Write-Output "ERROR: Unable to convert startupMem to int64."
        return $false
    }
    Write-Output "startupMem: $startupMem"
}

if ($null -eq $memWeight)
{
    Write-Output "ERROR: Test parameter memWeight was not specified"
    return $False
}
else 
{
    $memWeight = [Convert]::ToInt32($memWeight)
    if ($memWeight -lt 0 -or $memWeight -gt 100)
    {
        Write-Output "ERROR: Memory weight needs to be between 0 and 100."
        return $false
      }

    Write-Output "memWeight: $memWeight"
}

# Optional TestLogDir param
if ($null -eq $TestLogDir)
{
    $TestLogDir = $rootdir
}

# Change the working directory to where we need to be
cd $rootdir

# Source the TCUtils.ps1 file
. .\setupscripts\TCUtils.ps1

# Stop the VM
if (Get-VM -Name ${vmName} |  Where { $_.State -like "Running" }) 
{
    Write-Output "`nINFO: Stopping VM ${vmName}"
    Stop-VM ${vmName} -force

    if (-not $?) 
    {
        Write-Output "`nERROR: Unable to shut ${vmName} down (in order to set Memory parameters)"
        return $false
    }

    # wait for VM to finish shutting down
    $timeout = 60

    while (Get-VM -Name ${vmName} |  Where { $_.State -notlike "Off" })
    {
        if ($timeout -le 0)
        {
            Write-Output "`nERROR: Unable to shutdown ${vmName}"
            return $false
        }
        start-sleep -s 5
        $timeout = $timeout - 5
    }
}

# Configure DM
Set-VMMemory -vmName ${vmName} -ComputerName $hvServer -DynamicMemoryEnabled $DMenabled `
             -MinimumBytes $minMem -MaximumBytes $maxMem -StartupBytes $startupMem `
             -Priority $memWeight
if (-not $?)
{
    Write-Output "`nERROR: Unable to set Dynamic Memory for ${vmName}."
    Write-Output "DM enabled: $DMenabled"
    Write-Output "minMem: $minMem"
    Write-Output "maxMem: $maxMem"
    Write-Output "startupMem: $startupMem"
    Write-Output "memWeight: $memWeight"
    return $false
}
else
{
    Write-Output "`nConfiguring Dynamic Memory for ${vmName}: Success"
    Write-Output "Configuring Dynamic Memory for ${vmName}: Success" >> $summaryLog
}

# Start the VM
$timeout = 500
Write-Output "`nINFO: Starting VM ${vmName}"

$sts = Start-VM -Name ${vmName} -ComputerName $hvServer 
if (-not (WaitForVMToStartSSH $ipv4 $timeout ))
{
    Write-Output "ERROR: ${vmName} failed to start!"
    return $False
}
else
{
    Write-Output "INFO: Started VM ${vmName}"
}

# Now check if the udev rules are present 
$sts = RunRemoteScript $remoteScript

# Get remote log
Write-Output "`n###### Remote Log #######`n"
$logfilename = ".\$remoteScript.log"
Get-Content $logfilename
Write-Output "`n######## End Log ########`n"

# Final assertion
if (-not $sts[-1])
{
    Write-Output "Hot-Add udev rules present on VM ${vmName}: Failed"
    Write-Output "Hot-Add udev rules present on VM ${vmName}: Failed" >> $summaryLog
    del $logfilename
    return $False
}
else
{
    Write-Output "Hot-Add udev rules present on VM ${vmName}: Success"
    Write-Output "Hot-Add udev rules present on VM ${vmName}: Success" >> $summaryLog
    del $logfilename
    return $True
}
