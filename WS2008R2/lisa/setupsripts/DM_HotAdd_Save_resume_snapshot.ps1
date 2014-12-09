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
    

.Description
        Verif a VM that has had its Assigned Memory modified can
    be saved and restored.

    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:

        <testParams>
            <param>VM1Name=SuSE-DM-VM1</param>
            <param>VM2Name=SuSE-DM-VM2</param>
        </testParams>

    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "VM1Name=SuSE-DM-VM1;VM2Name=SuSE-DM-VM2"

    Thes PowerShell test case cripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($True or $False)
    to indicate if the script completed successfully or not.

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

#######################################################################
#
# WaitToEnterVMState()
#
# Description:
#     Wait up to 2 minutes for a VM to enter a specific state
#
#######################################################################
function WaitToEnterVMState([String] $name, [String] $server, [String] $state)
{
    $isInState = $False

    $count = 12

    while ($count -gt 0)
    {
        $vm = Get-VM -Name $name -ComputerName $server
        if (-not $vm)
        {
            return $False
        }

        if ($vm.State -eq $state)
        {
            $isInState = $True
            break
        }

        Start-Sleep -s 10
    }

    return $isInState
}


#######################################################################
#
# Description:
#
#######################################################################
function WaitForVMToStart([String] $name, [String] $server)
{
    $isSystemUp = $False

    $count = 1
    
    while ($count -gt 0)
    {
        # To Do - add a different check...
        Start-Sleep -S 10
        $count -= 1

        $isSystemUp = $True
    }

    return $isSystemUp
}
#########################################################################
#   
########################################################################
function checkresult()
{
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000    
     
    "Info :   pscp -q -i ssh\${sshKey} root@${ipv4}:$stateFile} ."
    while ($timeout -ne 0 )
    {
    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
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
                        "Info : state file contains Testcompleted"              
                        return $True                       
                        break   
                                     
                    }

                    if ($contents -eq $TestAborted)
                    {
                         "Info : Hot add failed. "                                  
                         return $False 
                          
                    }
                    #Start-Sleep -s 1
                    $timeout-- 

                    if ($timeout -eq 0)
                    {
                        "Error : Timed out on Test Running , Exiting test execution."
                        #exit
                        return $False  
                                             
                    }                                
                  
            }    
            else
            {
                LogMsg 6 "Warn : state file is empty"
                return $False
            }
            del $stateFile -ErrorAction "SilentlyContinue"
        }
        else
        {
             "Warn : ssh reported success, but state file was not copied"
             return $False
        }
    }
    else #
    {
        "Error : pscp exit status = $sts"
        "Error : unable to pull state.txt from VM."
        return $False
    }
    }
}


########################################################################

#######################################################################
##
# Create a script to run the stress tool.
# Copy the script to the Linux VM
# convery eol to the Linux format
# start the the pressure tool on the VM
# Stress tool 
#######################################################################
function runtest ()
{
    #"stressapptest -s 60 " | out-file -encoding ASCII -filepath startstress.sh
    .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\new_hotadd.sh root@${ipv4}:
    if (-not $?)
    {
      "Error: Unable to copy startstress.sh to the VM"
       return $False
    }
#del startstress.sh

#.\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix startstress.sh  2> /dev/null"
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix new_hotadd.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to run dos2unix on startstress.sh"
        return $False
    }
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "chmod +x new_hotadd.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to chmod +x new_hotadd.sh "
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "/etc/init.d/atd restart 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to start atd"
        return $False
    }
    #.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f startstress.sh now 2> /dev/null"
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f new_hotadd.sh now 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to submit startstress to atd"
        return $False
    }
     return $True      
}

#######################################################################
## Function to collect memory matrix
########################################################################
function memorymatrix()
{
# Wait a few seconds to give Hyper-V some time to detect the new
# memory demand from the VM.  Then collect new memory metrics.
#
    Start-Sleep -s 10
    
    $vm = Get-VM -Name $vmName -ComputerName $hvServer
    if (-not $vm)
    {
        "Error: VM ${vmName} does not exist"
        return $False
    }
 
    
    $script:afterDemand = $vm.MemoryDemand
    $script:AfterMaxmem = $vm.MemoryMaximum
    $script:AfterMemoryassigned  = $vm.MemoryAssigned 
    $script:afterMinimum = $vm2.MemoryMinimum

    $demandDelta = $afterDemand - $beforeDemand
    "Info : Before memory demand          :${beforeDemand}"
    "Info : After memory demand           :${afterDemand}"
    "Info : Memory Demand change by       :${demandDelta}"
    "Info : Memory Maximum Before Demand  :${MaximumBytes}"
    "Info : Memory Maximum After Demand   :${AfterMaxmem}"
    "Info : Memory Assigned Before Demand :${beforeMemoryassigned}"
    "Info : Memory Assigned After Demand  :${AfterMemoryassigned}"

    return $True 
}


#######################################################################
#
# Main script body
#
#######################################################################

$retVal = $false
$results = "Failed"

$summaryLog  = "${vmName}_summary.log"

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}


$sshKey = $null
$ipv4 = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    
    switch ($fields[0].Trim())
    {   
    "sshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
	"rootdir" { $rootDir = $fields[1].Trim() }
    default  {}       
    }
}

if ($null -eq $sshKey)
{
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4)
{
    "Error: Test parameter ipv4 was not specified"
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

# This sleep is required to get hv_balloon driver to report pressure to host.
#Start-Sleep -s 50

# Capture the load on VM befre running stress test .
$vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$MaximumBytes = $vm.MemoryMaximum 
$beforeDemand = $vm.MemoryDemand
$beforeMemoryassigned  = $vm.MemoryAssigned
$beforeMinimum = $vm.MemoryMinimum


 Start-Sleep -s 50
### Run the Stress test 

$sts = runtest
foreach ($line in $sts)
{
    $line
}
if (-not $($sts[-1]))
    {
         
        "Error: Running Stress test failed on VM.!!! exiting test case "
        "result = $results"
        exit 
    }


$sts = checkresult 
foreach ($line in $sts)
{
    $line
}
if (-not $($sts[-1]))
    {
        "Error: Hot Add failed on VM. check VM logs , exiting test case execution "
        "result = $results"
        exit 
    }

#Collect memory matrix 
$sts =memorymatrix
foreach ($line in $sts)
{
    $line
} 
if (-not $($sts[-1]))
    {       
        "Error: Collecting memory matrix failed on VM.!!! exiting test case "
        "result = $results"
        exit 
    }

    

#
# If the assignemd memory for VM1 was modified, try the actual
# a save and restore.

## Final Check to see if Assigned memory is not greater then Max memory . 

if ( $AfterMemoryassigned -gt $beforeMemoryassigned  )
{
    "INFO: Memory Assigned had increased under pressure"
}
else
{
    "Error: Memory Assigned had not increased under pressure"
     "result = $results"
      exit 
}
#

"INFO: Doing Save operation on VM"
Save-Vm -Name $vmName -ComputerName $hvServer
  if (-not (WaitToEnterVMState $vmName $hvServer "SAVED"))
   {
        "Error: Unable to cleanly shutdown the VM"
        return $False
   }

"INFO: Doing Restore operation on VM"
Start-VM -Name $vmName -ComputerName $hvServer
   if (-not (WaitForVMToStart $vmName $hvServer))
    {
        "Error: ${vmName} failed to resume"
        return $False
    }

## wait for VM to start ,
 Start-Sleep -s 5

 # Capture the load on VM 
$vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$Memoryassigned  = $vm.MemoryAssigned

echo "Save/Restore : Success " >> $summaryLog



 if ( $AfterMemoryassigned -eq $Memoryassigned  )
{
    "INFO: Memory Assigned had not changed after Save/Restore"
}
else
{
    "Error: Memory Assigned had changed after Save/Restore "
    "Error: Memory Assigned before Save/Restore was : $Memoryassigned  " 
    "Error: Memory Assigned After Save/Restore was : $AfterMemoryassigned  " 
    "result = $results"
     exit 
}


# Now Take VM snapshot will give snashot a name .

$SnapshotName = "Test"

"INFO: Taking Snapshot operation on VM"
Checkpoint-VM -Name $vmName -SnapshotName $SnapshotName -ComputerName $hvServer 
#if (-not (Get-VMSnapshot -VMName $vmName -Name $SnapshotName))
if (-not $?)
    {         
        "Error: Taking snapshot"
        "result = $results"       
        exit 
    }


"INFO: Restoring Snapshot operation on VM"
Restore-VMSnapshot -VMName $vmName -Name $SnapshotName -ComputerName $hvServer -Confirm:$false
if (-not $?)
    {         
        "Error: Restoring snapshot"
        "result = $results"
        exit 
    }

echo "Snapshot/Restore : Success " >> $summaryLog

# Capture the load on VM 
$vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$Memoryassigned  = $vm.MemoryAssigned

 if ( $AfterMemoryassigned -eq $Memoryassigned  )
{
    "INFO: Memory Assigned had not changed after Snapshot/Restore"
}
else
{
    "Error: Memory Assigned had changed after Snapshot/Restore "
    "result = $results"
    Remove-VMSnapshot -VMName $vmName -Name $SnapshotName -ComputerName $hvServer
     exit 
}

"INFO : After Snapshot Memoryassigned is  $Memoryassigned "

# Capture the load on VM 
$vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $vm)
{
    "Error: VM ${vmName} does not exist"
    return $False
}

$Memoryassigned  = $vm.MemoryAssigned

"INFO : Running Stress test again after snapshot"

$sts = runtest
foreach ($line in $sts)
{
    $line
}
if (-not $($sts[-1]))
    {
         
        "Error: Running Stress test failed on VM.!!! exiting test case "
        "result = $results"
        Remove-VMSnapshot -VMName $vmName -Name $SnapshotName -ComputerName $hvServer
        exit 
    }


$sts = checkresult 
foreach ($line in $sts)
{
    $line
}
if (-not $($sts[-1]))
    {
        "Error: Hot Add failed on VM. check VM logs , exiting test case execution "
        "result = $results"
        Remove-VMSnapshot -VMName $vmName -Name $SnapshotName -ComputerName $hvServer
        exit 
    }


#Collect memory matrix 
$sts =memorymatrix
foreach ($line in $sts)
{
    $line
} 
if (-not $($sts[-1]))
    {       
        "Error: Collecting memory matrix failed on VM.!!! exiting test case "
        "result = $results"
        Remove-VMSnapshot -VMName $vmName -Name $SnapshotName -ComputerName $hvServer
        exit 
    }


## Final Check to see if Assigned memory has increased . 

if ( $AfterMemoryassigned -gt $Memoryassigned  )
{
    "INFO : Assigned Memory has increased after stress run"
    echo "Hot ADD : Success " >> $summaryLog
    $results = "Passed"
    $retVal = $True
    
}


# Now delete the snapshot. 

"INFO: Deleting Snapshot $SnapshotName of VM"
Remove-VMSnapshot -VMName $vmName -Name $SnapshotName -ComputerName $hvServer 
if ( -not $?)
    {
         
        "Error: Deleting snapshot"       
    }


"Info : Test ${results}"

return $retVal

