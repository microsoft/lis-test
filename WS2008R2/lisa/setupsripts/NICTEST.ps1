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
function switchNIC() 
{
 $Error.Clear()

 $snic = Get-VMNIC -VM PPG_ICA -VMBus
 Write-Output $snic | Out-File -Append $summaryLog
 
 Set-VMNICSwitch $snic -Virtualswitch Internal
 if ($Error.Count -eq 0)
 {
  "Completed"
  $retVal = $true
 }
 else
  {
    "Error: Unable to Switch Network Adaptor Type"
    $Error[0].Exception
    return $False
  }
}
Write-Output $retVal 
return $retVal