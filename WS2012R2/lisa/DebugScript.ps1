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
    Debug context definition.

.Description
    This script defines debug context when running LISA with parameter
    -DebugScript. Optional parameters are -traceLevel -breakLine
    -breakVariable -breakCommand. It is also supported to customize
    debug context in this file(eg. break at certain condition).

.Parameter scriptPath
    Path to the powershell script

.Parameter vmName
    Name of the VM

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Test data for this test case

.Parameter debugConfig
    Debug configuration (hashtable):
    @{
        [sring]     script
        [int]       traceLevel=$traceLevel
        [int[]]     line=$breakLine
        [string[]]  variable
        [string[]]  command
    }

.Example
    lisa.ps1 run xml\HV_Sock.xml -debugScript All
    lisa.ps1 run xml\HV_Sock.xml -debugScript All -traceLevel 2
    lisa.ps1 run xml\HV_Sock.xml -debugScript .\setupscripts\HV_Sock_Basic.ps1
    lisa.ps1 run xml\HV_Sock.xml -debugScript .\setupscripts\HV_Sock_Basic.ps1 -traceLevel 2
    lisa.ps1 run xml\HV_Sock.xml -debugScript .\setupscripts\HV_Sock_Basic.ps1 -breakLine 53, 93
    lisa.ps1 run xml\HV_Sock.xml -debugScript .\setupscripts\HV_Sock_Basic.ps1 -traceLevel 2 -breakLine 53, 93 -breakVariable ReturnCode  -breakCommand InvokeCommand, TestPartI
#>

param([string] $scriptPath, [string] $vmName, [string] $hvServer, [string] $testParams, [hashtable] $debugConfig)

# Set breakpoints
foreach($line in $debugConfig.line){
    Set-PSBreakpoint -Script $scriptPath -Line $line
}
foreach($var in $debugConfig.variable){
    Set-PSBreakpoint -Script $scriptPath -Variable $var -Mode READWRITE
}
foreach($command in $debugConfig.command){
    Set-PSBreakpoint -Script $scriptPath -Command $command
}

# Set trace level
if (($debugConfig.traceLevel -eq 1) -or ($debugConfig.traceLevel -eq 2)){
    Set-PSDebug -Trace $debugConfig.traceLevel
}

# Customize debug context here
# Example: Break to manual debug mode at certain condition:
#   The following code snip sets a conditional breakpoint at variable
#   "server_exit_code" in script HV_Sock_Basic.ps1. When variable
#   "server_exit_code" is assigned a value other than 0, the job will
#   break to manual debug mode.
#
#   Set-PSBreakpoint -Script $scriptPath -Variable "server_exit_code" -Action {
#       if ($server_exit_code -ne 0) { break }
#   }

# Run Script in current context
. $scriptPath $vmName $hvServer $testParams
