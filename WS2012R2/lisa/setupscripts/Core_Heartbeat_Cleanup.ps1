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

Test-Path './heartbeat_params.info'
if (-not $?)
{
	return $True
}
$params = Get-Content './heartbeat_params.info' | Out-String | ConvertFrom-StringData

if ($params.vm_name)
{
    Write-Output "Info: Starting cleanup for the child VM"
    $sts = Stop-VM -Name $params.vm_name -ComputerName $hvServer -TurnOff
    if (-not $?)
    {
        Write-Output "Error: Unable to Shut Down VM $vmName1"

    }

    # Delete the child VM created
    $sts = Remove-VM -Name $params.vm_name -ComputerName $hvServer -Confirm:$false -Force
    if (-not $?)
    {
        Write-Output "Error: Cannot remove the child VM $vmName1"
    }
}

if ($params.child_vhd)
{
    # Delete VM VHD
    del $params.child_vhd
}

if ($params.test_vhd)
{
    # Delete partition
    Dismount-VHD -Path $params.test_vhd -ComputerName $params.hvServer

    # Delete VHD
    del $params.test_vhd
}

del './heartbeat_params.info'
return $True