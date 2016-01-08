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

########################################################################
# MUST keep this interface
########################################################################

function RunBenchmarking( [string]$logid, [string]$bisect_commit_id )
{
    # source the test parameter file
    . .\git-bisect-for-regression-params.ps1
    # source the function library
    . .\TCUtils.ps1    

    $badResult = 15
    $goodResult = 20

    $logFile = $logid + "-CLIENT-run-ntttcp-" + $bisect_commit_id + ".log"

    # Run performance benchmark
    echo "ntttcp -r -D" >  .\run-ntttcp.sh
    SendFileToVM $server_VM_ip $sshKey ./run-ntttcp.sh "run-ntttcp.sh" $true
    SendCommandToVM $server_VM_ip $sshKey "chmod 755 *.sh && ./run-ntttcp.sh"
    
    echo "ntttcp -s$server_VM_ip > $logFile"  > .\run-ntttcp.sh
    SendFileToVM $client_VM_ip    $sshKey ./run-ntttcp.sh "run-ntttcp.sh" $true
    SendCommandToVM $client_VM_ip $sshKey "chmod 755 *.sh && ./run-ntttcp.sh"
    
    start-sleep -seconds 65 # ntttcp test run duration: 60 seconds, then wait for extra 5 seconds before copying back log file
    GetFileFromVM $client_VM_ip $sshKey $logFile $logFile
    
    #Try to figure out the result is good or bad
    $thisResult = (Get-Content $logFile | Select-String "throughput" | Select-String "bps").ToString().Split(":")[-1].Replace("Gbps","")
    Write-Host "Test Result: $thisResult "
    echo "$(get-date -f "yyyy-MM-dd HH:mm")    $logid $bisect_commit_id $thisResult" >> git-bisect-status.log

    $result_is_good = $false
    if ([math]::abs($goodResult - $thisResult) -lt  [math]::abs($badResult - $thisResult) )
    {
        $result_is_good = $true
    }

    echo $logid"    "$bisect_commit_id"    "$thisResult >> D:\Test\00-ntttcp-all-tests.log
    return $result_is_good
}