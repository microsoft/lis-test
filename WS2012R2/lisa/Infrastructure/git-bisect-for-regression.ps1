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
#    Base VM requirement
#vm: 2 NICs:
#    NIC1: connect to internet to clone linux-next
#    NIC2: private network for test if want to run network tests
#vm: git-core installed
#vm: iperf3 installed
#vm: if ubuntu: apt-get install kernel-package
#vm: if ubuntu: apt-get install hv-kvp-daemon-init, or linux-cloud-tools-$(uname -r)
#vm: if ubuntu: apt-get install dos2unix
########################################################################



function WaitVMState([String] $ipv4, [String] $sshKey, [string] $state, [int] $interval)
{
    $file = "teststate.sig"
    Write-Host "INFO :wait for VM $ipv4 to the state: $state"

    switch ($state){
        SHUT_DOWN {
            $continueLoop = 300
            While( (Test-NetConnection -port 22 -ComputerName $ipv4 -InformationLevel Quiet) -eq $true ) {      
                Write-Host "." -NoNewLine
                Start-Sleep -Seconds $interval
                $continueLoop -= $interval
            }
            Start-Sleep -Seconds 10
            Write-Host "OK"
        }
        BOOT_UP {
            #sleep for sshd to start
            $continueLoop = 300
            While( (Test-NetConnection -port 22 -ComputerName $ipv4 -InformationLevel Quiet ) -ne $true ) {      
                Write-Host "." -NoNewLine
                Start-Sleep -Seconds $interval
                $continueLoop -= $interval
            }
            Write-Host "OK"
        }
        default {
            while ($true){
                $fileCopied = GetFileFromVM $ipv4 $sshKey $file $file
                if ($fileCopied -eq $true)
                {
                    $content = (Get-Content $file)
                    Write-Host "INFO :$ipv4 ==> $content"
                    if ( (Get-Content $file) -eq $state) 
                    {
                        break
                    }
                }
                Write-Host "." -NoNewLine
                sleep $interval
            }
            Write-Host "OK"
        }
    }
}

function InitVmUp([String] $vmName, [String] $hvServer, [string] $checkpointName)
{
    $v = Get-VM $vmName -ComputerName $hvServer
    if ($v -eq $null)
    {
        Write-Host "Error: ResetVM cannot find the VM $vmName on HyperV server $hvServer"  -ForegroundColor Red
        return
    }
    if ($v.State -ne "Off")
    {
        Stop-VM $vmName -ComputerName $hvServer -force | out-null
    }
    $v = Get-VM $vmName -ComputerName $hvServer
    if ($v.State -ne "Off")
    {
        Write-Host "Error: ResetVM cannot stop the VM $vmName on HyperV server $hvServer" -ForegroundColor Red
    }

    $snaps = Get-VMSnapshot $vmName -ComputerName $hvServer
    $snapshotFound = $false
    foreach($s in $snaps)
    {
        if ($s.Name -eq $checkpointName)
        {
            write-Host "INFO : ResetVM VM $vmName to checkpoint $checkpointName"
            Restore-VMSnapshot $s -Confirm:$false | out-null
            $snapshotFound = $true
            break
        }
    }

    $v = Get-VM $vmName -ComputerName $hvServer
    if ($snapshotFound)
    {
        if ($v.State -eq "Paused")
        {
            Stop-VM $vmName -ComputerName $hvServer -Force | out-null
        }
    }
    else
    {
        Write-Host "Error: ResetVM cannot find the checkpoint $checkpointName for the VM $vmName on HyperV server $hvServer"  -ForegroundColor Red
    }

    $continueLoop = 10
    $vmUp = $false
    While( ($continueLoop -gt 0) -and ($vmUp  -eq $false)) {
        Start-VM $vmName -ComputerName $hvServer | out-null
        $v = Get-VM $vmName -ComputerName $hvServer
        if ($v.State -eq "Running")
        {
            Write-Host "INFO : VM $vmName has been started"
            $vmUp = $true
            break
        }
        else
        {
            Write-Host "WARN : VM $vmName failed to start" -ForegroundColor Yellow
        }
        $continueLoop --
    }
    if ($vmUp  -eq $false){
        Write-Host "Error: VM $vmName failed to start" -ForegroundColor Red
        exit -1
    }

    # Source the TCUtils.ps1 file
    . .\TCUtils.ps1

    $continueLoop = 300
    $ipv4 = $null
    While( ($continueLoop -gt 0) -and ($ipv4 -eq $null)) {
        $ipv4 = GetIPv4 $vmName $hvServer
        Write-Host "." -NoNewLine
        Start-Sleep -Seconds 2
        $continueLoop -= 2
    }

    #sleep for sshd to start
    $continueLoop = 300
    While( (Test-NetConnection -port 22 -ComputerName $ipv4  -InformationLevel Quiet) -ne $true ) {      
        Write-Host "." -NoNewLine
        Start-Sleep -Seconds 2
        $continueLoop -= 2
    }
    Write-Host "OK"
}

# source the test parameter file
. .\git-bisect-for-regression-params.ps1

if((test-path ".\TCUtils.ps1 ") -eq $false )
{
    write-host "TCUtils.ps1 not found"
    exit -1
}

. .\TCUtils.ps1
 

############################################
# Init VM with linux-next clone.
# Make a base linux-next snapshot
############################################
# ***** preapre VM for test
InitVmUp $server_VM_Name $server_Host_ip $icabase_checkpoint
InitVmUp $client_VM_Name $client_Host_ip $icabase_checkpoint

echo "rm -rf ./teststate.sig" 	                        >  clone-linux.sh
echo "git clone $linuxnext $linuxnextfolder "       	>> clone-linux.sh
echo "echo CLONE_FINISHED > ./teststate.sig " 	        >> clone-linux.sh    
echo "sleep 12" 								        >> clone-linux.sh
echo "init 0" 									        >> clone-linux.sh

SendFileToVM 		$server_VM_ip $sshKey ./clone-linux.sh "clone-linux.sh" $true
Write-Host "INFO: Running clone-linux.sh on VM $server_VM_ip ... "
SendCommandToVM  	$server_VM_ip $sshKey "chmod 755 clone-linux.sh && ./clone-linux.sh"

SendFileToVM 		$client_VM_ip $sshKey ./clone-linux.sh "clone-linux.sh" $true
Write-Host "INFO: Running clone-linux.sh on VM $client_VM_ip ... "
SendCommandToVM  	$client_VM_ip $sshKey "chmod 755 clone-linux.sh && ./clone-linux.sh"

WaitVMState $server_VM_ip $sshKey "SHUT_DOWN" 5
WaitVMState $client_VM_ip $sshKey "SHUT_DOWN" 5

Checkpoint-VM -Name $server_VM_Name -ComputerName $server_Host_ip -SnapshotName $linux_next_base_checkpoint -Confirm:$False
Checkpoint-VM -Name $client_VM_Name -ComputerName $client_Host_ip -SnapshotName $linux_next_base_checkpoint -Confirm:$False

Copy-Item $portable_git_location $local_git_location -recurse -ErrorAction SilentlyContinue
cmd /c "robocopy /mir /R:2 /W:1 /nfl /ndl $portable_git_location $local_git_location"
cd $test_folder
Remove-Item $linuxnextfolder -Recurse -Force -ErrorAction SilentlyContinue
if (test-path $linuxnextfolder)
{
    Write-Host "Try to delete previous cloned repo but failed!" -ForegroundColor Red
    exit -1
}

# ***** init controller's git repo (run on Windows)
echo "lastKnownBadcommit=$lastKnownBadcommit"            >   .\const.sh
echo "lastKnownGoodcommit=$lastKnownGoodcommit "         >>  .\const.sh
echo "topCommitQuality=$topCommitQuality "               >>  .\const.sh

echo "cd $test_folder_bash"                              >   .\git-clone-init.sh
echo "dos2unix *.sh"                                     >>  .\git-clone-init.sh
echo "source ./const.sh "                                >>  .\git-clone-init.sh

echo "if [ ! -d $linuxnextfolder ]; then  "              >>  .\git-clone-init.sh
echo "    git clone $linuxnext $linuxnextfolder "        >>  .\git-clone-init.sh
echo "    cd $linuxnextfolder "                          >>  .\git-clone-init.sh  
echo "    pwd "                                          >>  .\git-clone-init.sh  
echo "    echo [BAD ]: `$lastKnownBadcommit "            >>  .\git-clone-init.sh  
echo "    echo [GOOD]: `$lastKnownGoodcommit "           >>  .\git-clone-init.sh  
echo "    pwd "                                          >>  .\git-clone-init.sh  
echo "    if [ ! -z `"`$lastKnownBadcommit`" ]; then"    >>  .\git-clone-init.sh
echo "        echo Reset to last known bad commit"       >>  .\git-clone-init.sh
echo "        git reset --hard `$lastKnownBadcommit "    >>  .\git-clone-init.sh
echo "    fi"                                            >>  .\git-clone-init.sh
echo "    echo Starting git bisect ... "                 >>  .\git-clone-init.sh 
echo "    git bisect start "                             >>  .\git-clone-init.sh 
echo "    git bisect good `$lastKnownGoodcommit"         >>  .\git-clone-init.sh 

echo "else"                                              >>  .\git-clone-init.sh
echo "    cd $linuxnextfolder "                          >>  .\git-clone-init.sh  
echo "    pwd "                                          >>  .\git-clone-init.sh  
echo "    if [ `"`$topCommitQuality`" == `"BAD`" ] ; then " >>  .\git-clone-init.sh
echo "        git bisect bad  > ../git-bisect.log "      >>  .\git-clone-init.sh
echo "    else "                                         >>  .\git-clone-init.sh
echo "        git bisect good > ../git-bisect.log "      >>  .\git-clone-init.sh
echo "    fi "                                           >>  .\git-clone-init.sh
echo "    git log | head -1 > ../bisectcommit.tmp"       >>  .\git-clone-init.sh
echo "fi"                                                >>  .\git-clone-init.sh

$file = $test_folder + "\git-clone-init.sh"
cmd /c  "$local_git_location\usr\bin\dos2unix.exe -q $file > nul 2>&1"
cmd /c  "$local_git_location\git-bash.exe $file"
if (test-path $linuxnextfolder)
{
    Write-Host "Repo cloned: $linuxnext ==> $linuxnextfolder"
}

############################################
# Find a bisect commit id
# and then test it: good, or bad?
############################################
$runid = 1
while ($true)
{
    # preapre VM for test
    InitVmUp $server_VM_Name $server_Host_ip $linux_next_base_checkpoint
    InitVmUp $client_VM_Name $client_Host_ip $linux_next_base_checkpoint
    
    # Find the commit
    Remove-Item .\bisectcommit.tmp -Force -ErrorAction SilentlyContinue
    cmd /c  "$local_git_location\git-bash.exe         $file"

    $commitfile = (Get-Content .\bisectcommit.tmp)
    $bisect_commit_id = $commitfile.Split(" ")[1];
    Write-Host "------------------------------------------------------------"
    Write-Host "Commit id parsed: $bisect_commit_id" -ForegroundColor Yellow
    type .\git-bisect.log
    if ( (Get-Content .\git-bisect.log).Contains("is the first bad commit"))
    {
        Write-Host "************************************************************"
        Write-Host "FINISHED" -ForegroundColor Red
        break
    }

    # Apply this commit and build linux-next
    $log = "reset-and-build-" + $bisect_commit_id + ".log"
    echo "rm -rf ./teststate.sig "				>  .\reset-and-build.sh
    echo "cd $linuxnextfolder" 					>> .\reset-and-build.sh
    echo "mv ../$distro_build_script ." 			>> .\reset-and-build.sh
    echo "git reset --hard $bisect_commit_id > ../$log" 	>> .\reset-and-build.sh
    echo "./$distro_build_script >> ../$log" 			>> .\reset-and-build.sh
    echo "echo BUILD_FINISHED > ../teststate.sig" 		>> .\reset-and-build.sh
    echo "init 6" 										>> .\reset-and-build.sh

    SendFileToVM $server_VM_ip $sshKey ./const.sh 			 "const.sh" $true
    SendFileToVM $server_VM_ip $sshKey $distro_build_script  $distro_build_script $true
    SendFileToVM $server_VM_ip $sshKey ./reset-and-build.sh  "reset-and-build.sh" $true
    SendCommandToVM $server_VM_ip $sshKey "chmod 755 *.sh && ./reset-and-build.sh"
    
    SendFileToVM $client_VM_ip $sshKey ./const.sh 			 "const.sh" $true
    SendFileToVM $client_VM_ip $sshKey $distro_build_script  $distro_build_script $true
    SendFileToVM $client_VM_ip $sshKey ./reset-and-build.sh  "reset-and-build.sh" $true
    SendCommandToVM $client_VM_ip $sshKey "chmod 755 *.sh && ./reset-and-build.sh"
    
    WaitVMState $server_VM_ip $sshKey "BUILD_FINISHED" 5
    WaitVMState $client_VM_ip $sshKey "BUILD_FINISHED" 5
    
    # to make sure the completed shutdown and then wait for bootup
    Start-Sleep -Seconds 10
    
    WaitVMState $server_VM_ip $sshKey "BOOT_UP" 5
    WaitVMState $client_VM_ip $sshKey "BOOT_UP" 5
    
    # get reset-and-build log back
    $serverlog = ("{0:00}" -f $runid ) + "-SERVER-" + $log
    $clientlog = ("{0:00}" -f $runid ) + "-CLIENT-" + $log
    GetFileFromVM $server_VM_ip $sshKey $log $serverlog
    GetFileFromVM $client_VM_ip $sshKey $log $clientlog
    
    # Test this commit
    echo "ntttcp -r -D" >  .\run-ntttcp.sh
    SendFileToVM $server_VM_ip $sshKey ./run-ntttcp.sh "run-ntttcp.sh" $true
    SendCommandToVM $server_VM_ip $sshKey "chmod 755 *.sh && ./run-ntttcp.sh"
    
    $log = ("{0:00}" -f $runid ) + "-CLIENT-run-ntttcp-" + $bisect_commit_id + ".log"
    echo "rm -rf ./teststate.sig "      	        >  .\run-ntttcp.sh
    echo "ntttcp -s$server_VM_ip > $log" 	        >> .\run-ntttcp.sh
    echo "echo TEST_FINISHED > ./teststate.sig" 	>> .\run-ntttcp.sh
    SendFileToVM $client_VM_ip    $sshKey ./run-ntttcp.sh "run-ntttcp.sh" $true
    SendCommandToVM $client_VM_ip $sshKey "chmod 755 *.sh && .\run-ntttcp.sh"
    
    WaitVMState $client_VM_ip $sshKey "TEST_FINISHED" 5
    GetFileFromVM $client_VM_ip $sshKey $log $log

    #Try to figure out the result is good or bad
    $thisResult = (Get-Content $log | Select-String "throughput").Split(":")[2].Replace("Gbps","")

    Write-Host "Test Result: $thisResult "
    $result_is_good = $false
    if ([math]::abs($goodResult - $thisResult) -lt  [math]::abs($badResult - $thisResult) )
    {
        $result_is_good = $true
    }

    if ($result_is_good -eq $true) 
    {
        $lastKnownGoodcommit = $bisect_commit_id
        Write-Host "Commit id: $bisect_commit_id is good" -ForegroundColor Green
        echo "topCommitQuality=GOOD"              >  .\const.sh
    }
    else 
    {
        $lastKnownBadcommit = $bisect_commit_id
        Write-Host "Commit id: $bisect_commit_id is bad" -ForegroundColor Yellow
        echo "topCommitQuality=BAD"               >  .\const.sh
    }
    $runid ++
}
