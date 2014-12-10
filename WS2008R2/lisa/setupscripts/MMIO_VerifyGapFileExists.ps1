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
    

.Parameter vmName
    

.Parameter hvServer
    

.Parameter testParams
    

.Example
    
#>
############################################################################
# MMIO_VerifyGapFileExists.ps1
#
# Description:
# This powershell setup script verifies if the ${vmName}_gapSize.sh file 
# exists in the specified file path and copy it to the VM.
# 
# This script should be used as a pretest script for MMIO testscript. 
# It expects the VM in turned on state.
############################################################################

param ([string] $vmName, [string] $hvServer, [string] $sshKey, [string] $ipv4, [string] $testparams)

#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}


"  vmName    = ${vmName}"
"  hvServer  = ${hvServer}"
"  testParams= ${testParams}"

#
# Parse the testParams string
#
$sshKey = $null
$ipv4 = $null
$rootDir = $null

$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        # Just ignore it
        continue
    }
    
    $val = $tokens[1].Trim()
    
    switch($tokens[0].Trim().ToLower())
    {
    "sshkey"  { $sshKey = $val }
    "ipv4"    { $ipv4 = $val }
    "rootdir" { $rootDir = $val }
    default  { continue }
    }
}

#
# Make sure the required testParams were found
#
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

if (-not $ipv4)
{
    "Error: testParams is missing the ipv4 parameter"
    return $False
}

"  sshKey  = ${sshKey}"
"  ipv4    = ${ipv4}"
"  rootDir = ${rootDir}"

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Verifying if the file exists
#
if (Test-Path .\remote-scripts\ica\${vmName}_gapSize.sh)
{
    "Info : Gap File Found"

    #
    # Copying files to VM with appropriate format and permissions
    #
    .\bin\pscp.exe -i ssh\${sshKey} ".\remote-scripts\bin\MMIO_get_vm_name.sh" root@${ipv4}:
    if(!$?)
    {
        "Error: File Can not be copied"
        return $retVal
    } 
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "chmod +x /root/MMIO_get_vm_name.sh 2> /dev/null"
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix /root/MMIO_get_vm_name.sh 2> /dev/null"
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "sh /root/MMIO_get_vm_name.sh $vmName 2> /dev/null"
    .\bin\pscp.exe -i ssh\${sshKey} ".\remote-scripts\ica\${vmName}_gapSize.sh" root@${ipv4}: 
    if(!$?)
    {
        "Error: Failed to copy ${vmName}_gapSize.sh file"
        return $retVal
    }
    .\bin\plink -i ssh\${sshKey} root@${ipv4} "dos2unix /root/${vmName}_gapSize.sh 2> /dev/null"
    $retval = $True
} 
else
{
    "Error: Gap File Not Found!"
    return $retval
}

#
# Updating the summary log with Testcase ID details
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers MMIO TC-2.3.1 and TC-2.3.3" | Out-File $summaryLog

return $retval