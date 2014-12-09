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
    This is a function to send request to a named pipe, which represents
    the serial port of specified VM. This function supports connecting to
    remote Hyper-V server by specifying $VMHost, if the remote Hyper-V
    server has remote management enabled.
    
#>

param (
        $VMHost = "localhost",
        $Timeout = 5,
        $Pipe,
        $Command
)

function SendICARequest($VMHost, $Timeout, $Pipe, $Command)
{
    $session = New-PSSession -ComputerName $VMHost
    if ($session -eq $null) {
        Write-Warning "Please do 'winrm quickconfig' on $VMHost first."
        return $null
    }
    $response = Invoke-Command -Session $session -ScriptBlock {
        param ( $Timeout, $Pipe, $Command )
        $job = Start-Job -ScriptBlock {
            param ( $Pipe, $Command )

            Add-Type -AssemblyName System.Core
            $p = New-Object `
                    -TypeName System.IO.Pipes.NamedPipeClientStream `
                    -ArgumentList $Pipe
            $p.Connect()
            $writer = New-Object -TypeName System.IO.StreamWriter `
                                 -ArgumentList $p
            $reader = New-Object -TypeName System.IO.StreamReader `
                                 -ArgumentList $p
            $writer.AutoFlush = $true
            $writer.WriteLine($Command)
            $response = $reader.ReadLine()
            $writer.Close()
            $reader.Close()
            $p.Close()
            $response
        } -ArgumentList ($Pipe,$Command)
        Wait-Job -Job $job -Timeout $Timeout | Out-Null
        $response = Receive-Job -Job $job
        $response
    } -ArgumentList ($Timeout,$Pipe,$Command)
    Remove-PSSession -Session $session | Out-Null
    return $response
}
$response = SendICARequest $VMHost $Timeout $Pipe $Command
if ($response -eq $null -or $response -eq "")
{
    $WAIT_TIMEOUT = 258
    # Don't write output. It keeps the same behavior with icaserial.c
    # Write-Host "badCmd $WAIT_TIMEOUT"
    exit $WAIT_TIMEOUT
}
else
{
    Write-Host "$response"
    exit 0
}
