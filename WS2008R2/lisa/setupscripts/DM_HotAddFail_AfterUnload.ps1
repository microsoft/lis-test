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
                       
                       
                        "Error :Hot Add should not have succed "
                         return $False   
                                     
                    }

                    if ($contents -eq $TestAborted)
                    {
                         "Info : Hot add failed. "                                  
                         return $True
                          
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
    .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\hot_add_memory.sh root@${ipv4}:
    if (-not $?)
    {
      "Error: Unable to copy startstress.sh to the VM"
       return $False
    }
#del startstress.sh

#.\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix startstress.sh  2> /dev/null"
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix hot_add_memory.sh  2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to run dos2unix on startstress.sh"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "/etc/init.d/atd restart 2> /dev/null"
    if (-not $?)
    {
        "Error: Unable to start atd"
        return $False
    }

#.\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f startstress.sh now 2> /dev/null"
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "at -f hot_add_memory.sh now 2> /dev/null"
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

# Set result to false 

$results = "Failed"

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
        
    "sshKey" { $sshKey  = $fields[1].Trim() }
    "ipv4"   { $ipv4    = $fields[1].Trim() }
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


# Issue the rmmod command to remove hv_balloon on the Linux VM

"INFO : Removing hv_balloon from linux VM"
bin\plink.exe -i ssh\${sshKey} root@${ipv4} "rmmod hv_balloon"
if (-not $?)
{
    "ERROR: Removing hv_ballonn"
    return $False
    exit
}


"INFO : After removing hv_balloon running stress to try to Hot-ADD"
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



$sts = checkresult 
foreach ($line in $sts)
{
    $line
}
if (-not $($sts[-1]))
    {
        "Error: Hot Add Succeeded on VM. check VM logs , exiting test case execution "
        "result = $results"
        exit 
    }


## Final Check to see if Assigned memory has not increased.

if ( $AfterMemoryassigned -eq $beforeMemoryassigned  )
{
     "INFO: Memory assigned has not increased after stress test."
     $results = "Passed"
     $retVal = $True   
}
else
{
    "Error: Memory Assigned had increased under pressure"
}

#
"Info : Test ${results}"


return $retVal

