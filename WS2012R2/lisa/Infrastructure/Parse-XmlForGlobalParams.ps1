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
    Parse the LISA XML file.

.Description
    Parse the LISA XML file and register the global test parameters to the test client.
    This script needs command support of WttCmd. Please don't run this script if you don't have WttCmd installed in the test client. 
    
.Parameter XmlFilename
    The LISA XML file which defined the LISA test. 

.Exmple
    Parse-XmlForGlobalParams.ps1 SimpleLisaTest.xml

#>
param( [string]$XmlFilename )

#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript "Parse-XmlForGlobalParams.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Parse-XmlForGlobalParams.ps1]..." -foregroundcolor cyan
Write-Host "`$XmlFilename    = $XmlFilename" 

#----------------------------------------------------------------------------
# Verify XML file and read it
#----------------------------------------------------------------------------
if ($XmlFilename -eq $null -or $XmlFilename -eq "")
{
    Throw "Parameter XmlFilename is required."
}
else
{
    if (! (test-path $XmlFilename))
    {
        write-host -f Red "Error: XML config file '$XmlFilename' does not exist."
        Throw "Parameter XmlFilename is required."
    }
}

$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
if ($null -eq $xmlConfig)
{
    write-host -f Red "Error: Unable to parse the .xml file"
    return $false
}

#----------------------------------------------------------------------------
# Get the VM defined in the XML file
#----------------------------------------------------------------------------
$numberOfVMs = $xmlConfig.config.VMs.ChildNodes.Count
$VMName = [string]::Empty

Write-Host "Number of VMs defined in the XML file: $numberOfVMs"

if ($numberOfVMs -eq 0)
{
    Throw "No VM is defined in the LISA XML file."
}
elseif ($numberOfVMs -gt 1)
{
    #Concatenation all VM names into a string, split by : 
    foreach($node in $xmlConfig.config.VMs.ChildNodes)
    {
        $VMName = $VMName + ":" + $node.vmName + "@" + $node.hvServer
    }
    #remove the first separator
    $VMName = $VMName.Substring(1, $VMName.Length-1)
    Write-Host "All the VMs will be concatenated as (separator char ':'): $VMName"
}
else
{
    $VMName = $xmlConfig.config.VMs.VM.VMName
    Write-Host "The VM collected from the XML: $VMName"
}

#----------------------------------------------------------------------------
# Get the Log Folder defined in the XML file
#----------------------------------------------------------------------------
$logDir = $xmlConfig.config.global.logfileRootDir
Write-Host "Log Folder defined in the XML file: $logDir"

#----------------------------------------------------------------------------
# Write the value to WTT Client's SysInitKey
#----------------------------------------------------------------------------
cmd /c "wttcmd.exe /SysInitKey /Key:VMNameBeingTested /Value:$VMName"
cmd /c "wttcmd.exe /SysInitKey /Key:LocalTestLogDir /Value:$logDir"

Write-Host "Params have been set to the WTT Client machine by WttCmd."

Write-Host "Running [Parse-XmlForGlobalParams.ps1] FINISHED (NOT VERIFIED)."

Stop-Transcript
exit 
