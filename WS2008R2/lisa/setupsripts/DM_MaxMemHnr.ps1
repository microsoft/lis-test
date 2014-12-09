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
        This is a PowerShell test case script that runs on the on
    the ICA host rather than the VM.

    DN_HonorMaxMem  will check to see if VM's Assigned memory of VM does not get incresed beyon Max memory assigned under pressure
    
    The ICA scripts will always pass the vmName, hvServer, and a
    string of testParams to the PowerShell test case script. For
    example, if the <testParams> section was written as:
          <testParams>  
                <param>vm1Name=OpenSuse-DM-VM1</param>
               <param>vm1MinMem=256MB</param>
               <param>vm1MaxMem=9000MB</param>
               <param>vm1StartMem=9000MB</param>
               <param>vm1MemWeight=100</param>      
           </testParams>  
    The string passed in the testParams variable to the PowerShell
    test case script script would be:

        "HeartBeatTimeout=60;TestCaseTimeout=300"

    Thes PowerShell test case cripts need to parse the testParam
    string to find any parameters it needs.

    All setup and cleanup scripts must return a boolean ($true or $false)
    to indicate if the script completed successfully or not.
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

### import ConfigureDynamicMemory function 




#######################################################################
#
# ConvertToMemSize()
#
# Description:
#    Convert a string from one of the following formats to
#    a long int:
#        1024MB - Memory size in MB
#        1GB    - Memory size in GB
#        50%    - Memory size as a percent of system memory
#
#######################################################################
function ConvertToMemSize([String] $memString, [Int64] $memCapacity)
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
        $memPercent = [Convert]::ToDouble("0." + $memString.Replace("%",""))
        $num = [Int64] ($memPercent * $memCapacity)

        # Align on a 2MB boundry
        $memSize = [Int64](([Int64] ($num / 2MB)) * 2MB)
    }
    else
    {
        $memSize = -1
    }

    return $memSize
}
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
                        return $True
                        "Info : state file contains Testcompleted"
                        break             
                    }

                    if ($contents -eq $TestAborted)
                    {
                         "Error : Error running Stress Test " 
                          #exit         
                          return $False
                          break
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

## Function to collect memory matrix

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


$summaryLog  = "${vmName}_summary.log"
echo "Covers : DM 2.4.2 ,2.3.8 " >> $summaryLog

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
$rootDir = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
       switch ($fields[0].Trim())
    {
        
    "sshKey"  { $sshKey  = $fields[1].Trim() }
    "ipv4"    { $ipv4    = $fields[1].Trim() }
    "rootDir" { $rootDir = $fields[1].Trim() }
    "vm1NewMaxMem" { $VMNewMaxMem =  $fields[1].Trim() }
    default   {}       
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

if ($rootDir)
{
    if ((Test-Path $rootDir))
    {
        cd $rootDir
    }
}

# Get free physical Memory

#$mem = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $hvServer
#$freememory= $mem.FreePhysicalMemory

# Get host memory and get new Max memory body
#
#######################################################################



$hostInfo = Get-VMHost -ComputerName $hvServer
   if (-not $hostInfo)
   {
       "Error: Unable to get VM Host information for server ${hvServer}"
       return $False
   }

$hostMemCapacity = $hostInfo.MemoryCapacity

$VMNewMaxMem = ConvertToMemSize $VMNewMaxMem $hostMemCapacity
   if ($memSize -eq -1)
   {
       "Error: Unable to convert ${VMNewMaxMem} to memSize for VM ${vmName}"
       return $False
   }

# This sleep is required to get hv_balloon driver to report pressure to host.
Start-Sleep -s 50

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
 
# Set result to false 

$results = "Failed"


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
if (-not $sts[-1])
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
if (-not $sts[-1])
    {       
        "Error: Collecting memory matrix failed on VM.!!! exiting test case "
        "result = $results"
        exit 
    }

echo "Hot ADD : Success " >> $summaryLog

## To Check if New Max Memory is greater then previous value
if ($VMNewMaxMem -lt  $MaximumBytes)
{
    "Error: New Memory maximum has to be greater then exisiting Max Memory."
}


## Set New Max Memory without shutting down VM . 

Set-VMMemory -VMName $vmName -MaximumBytes $VMNewMaxMem -ComputerName $hvServer
if (-not $?)
    {
        "Error: Unable to set MaximumBytes for VM ${vmName}"
        return $False
    }

"Info : New maximum memory assigned is       : $VMNewMaxMem"

echo " New maximum memory assigned is : $VMNewMaxMem" >> $summaryLog

# Capture the new load on VM befre running stress test again .

$MaximumBytes = $vm.MemoryMaximum 
$beforeDemand = $vm.MemoryDemand
$beforeMemoryassigned  = $vm.MemoryAssigned



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

## Final Check to see if Assigned memory is not greater then Max memory . 

if ( $AfterMemoryassigned -gt $AfterMaxmem  )
{
    "Error: Memory Maximum had increased under pressure"
}
else
{
    echo "Hot ADD : Success " >> $summaryLog
    $results = "Passed"
    $retVal = $True
}

#
#

"Info : Test ${results}"

return $retVal

