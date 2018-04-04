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
.synopsis
    PowerPlan check.
.Description
    Check the PowerPlan if it is set to High Performance.
#>

#############################################################
#
# Main script body
#
#############################################################
$retVal = $false

# Get PowerPlan

$status=Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan -Filter "ElementName = 'High Performance'" | select -ExpandProperty IsActive

if ($status -eq $True)
{            
    Write-Output "Success : PowerPlan is on High Performance."              
    $retVal = $true
}
else{
    $process = Start-Process powercfg.exe -ArgumentList "/setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
       Throw "Error: Failed to set PowerPlan to High Performance"
    }
    $hp = Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan -Filter "ElementName = 'High Performance'" | select -ExpandProperty IsActive
    if ($hp -eq $True)
    {
        Write-Output "Success : PowerPlan High Performance activated."
        $retVal = $true
    }
    else{

        Write-Output "FAILED: PowerPlan could no be set to High Performance."
    }
}

return $retVal