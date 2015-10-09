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
# Base VM requirements:
# vm: 2 NICs:
#    NIC1: connect to internet to clone linux-next
#    NIC2: private network for test if want to run network tests
# vm: git-core installed
# vm: NTTTCP-for-Linux installed for network throughput performance test. 
#     See NTTTCP-for-Linux here: https://github.com/Microsoft/ntttcp-for-linux
# vm: if ubuntu: apt-get install kernel-package, so that we can build kernel package
# vm: if ubuntu: apt-get install hv-kvp-daemon-init, or linux-cloud-tools-$(uname -r), to install kvp daemon
# vm: if ubuntu: apt-get install dos2unix
########################################################################
# Other base VM configuration considerations:
# 1) configure VM so that we can use provided *.ppk key file to run commands/copy files with the Linux VM
# 2) If multiple VMs required, for example, running network tests, then configure the VMs to make sure 
#    password/key is not required when scp file between them
# 3) Install above tools
# 4) Create a root checkpoint for those VMs (for example, Lisabase). And configure the params file: 
#    git-bisect-for-regression-params.ps1
########################################################################
# Test folder files:
#    /TEST
#        /bin
#             /plink.exe
#             /pscp.exe
#             /dos2unix.exe, and its dependencies as below. all of them can be found from git for Windows
#             /msys-2.0.dll
#             /msys-iconv-2.dll
#             /msys-intl-8.dll
#        /ssh
#             /id_rsa.ppk
#             /id_rsa.pub
#        /build-ubuntu.sh
#        /git-bisect-for-regression.ps1
#        /git-bisect-for-regression-params.ps1
#        /TCUtils.ps1  #this can be found from https://github.com/LIS/lis-test/tree/master/WS2012R2/lisa/setupscripts/TCUtils.ps1
########################################################################

function WaitVMState([String] $ipv4, [String] $sshKey, [string] $state )
{
    $file = "teststate.sig"
    Write-Host "INFO :wait for VM $ipv4 to the state: $state"

    $success = $false
    switch ($state){
        SHUT_DOWN {
            $continueLoop = 60
            While( $success -eq $false -and $continueLoop -gt 0) {
                $continueLoop --
                if ($continueLoop % 60 -eq 0)
                {
                    Write-Host " "
                }
                Write-Host "." -NoNewLine
                
                Start-Sleep -Seconds 5
                $success = (Test-NetConnection -port 22 -ComputerName $ipv4 -InformationLevel Quiet)
            }
            Write-Host "OK"
        }
        BOOT_UP {
            #sleep for sshd to start
            $continueLoop = 60
            While( $success -eq $false -and $continueLoop -gt 0) {
                $continueLoop --
                if ($continueLoop % 60 -eq 0)
                {
                    Write-Host " "
                }
                Write-Host "." -NoNewLine
                
                Start-Sleep -Seconds 5
                $success = (Test-NetConnection -port 22 -ComputerName $ipv4 -InformationLevel Quiet )     
            }
            Write-Host "OK"
        }
        default {
            $continueLoop = 1000
            while ($true){
                $continueLoop --
                if ($continueLoop % 60 -eq 0)
                {
                    Write-Host " "
                }
                Write-Host "." -NoNewLine
                
                $fileCopied = GetFileFromVM $ipv4 $sshKey $file $file
                if ($fileCopied -eq $true)
                {
                    $content = (Get-Content $file)
                    if ( (Get-Content $file).Contains($state) ) 
                    {
                        $success = $true
                        break
                    }
                }
                Start-Sleep -Seconds 5
            }
            Write-Host "OK"
        }
    }
    return $success
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

function CheckVmKernelVersion([String] $ipv4, [String] $sshKey)
{
    # Source the TCUtils.ps1 file
    . .\TCUtils.ps1
    SendCommandToVM      $ipv4 $sshKey "uname -r > teststate.sig"
    # make sure above command executing finished
    Start-Sleep -Seconds 5  
    SendCommandToVM      $ipv4 $sshKey "echo KERNEL_VERSION >> teststate.sig"
    WaitVMState $ipv4 $sshKey "KERNEL_VERSION" 

    GetFileFromVM $ipv4 $sshKey "teststate.sig" "teststate.sig"
    return (Get-Content "teststate.sig")
}

############################################
############################################
#
# THIS IS THE BEGIN OF THIS SCRIPT
#
############################################
############################################
# source the test parameter file
if((test-path ".\git-bisect-for-regression-params.ps1 ") -eq $false )
{
    write-host "git-bisect-for-regression-params.ps1 not found"
    exit -1
}
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
InitVmUp $server_VM_Name $server_Host_ip $icabase_checkpoint
InitVmUp $client_VM_Name $client_Host_ip $icabase_checkpoint

echo "lastKnownBadcommit=$lastKnownBadcommit"            >   .\const.sh
echo "lastKnownGoodcommit=$lastKnownGoodcommit "         >>  .\const.sh
echo "topCommitQuality=$topCommitQuality "               >>  .\const.sh

echo "dos2unix *.sh"                                     >  .\drive-bisect.sh
echo "source ./const.sh "                                >> .\drive-bisect.sh
echo "rm -rf ./teststate.sig"                            >> .\drive-bisect.sh

echo "if [ ! -d $linuxnextfolder ]; then  "              >> .\drive-bisect.sh
echo "    git clone $linuxnext $linuxnextfolder "        >> .\drive-bisect.sh
echo "    cd $linuxnextfolder"                           >> .\drive-bisect.sh
echo "    echo [BAD ]: `$lastKnownBadcommit "            >> .\drive-bisect.sh  
echo "    echo [GOOD]: `$lastKnownGoodcommit "           >> .\drive-bisect.sh  
echo "    if [ ! -z `"`$lastKnownBadcommit`" ]; then"  >> .\drive-bisect.sh
echo "        echo Reset to last known bad commit"       >> .\drive-bisect.sh
echo "        git reset --hard `$lastKnownBadcommit "    >> .\drive-bisect.sh
echo "    fi"                                            >> .\drive-bisect.sh
echo "    echo Starting git bisect ... "                 >> .\drive-bisect.sh 
echo "    git bisect start "                             >> .\drive-bisect.sh 
echo "    git bisect good `$lastKnownGoodcommit"         >> .\drive-bisect.sh 
echo "    echo INIT_FINISHED > ../teststate.sig "          >> .\drive-bisect.sh    

echo "else"                                              >> .\drive-bisect.sh
echo "    cd $linuxnextfolder "                          >> .\drive-bisect.sh  
echo "    pwd "                                          >> .\drive-bisect.sh  
echo "    if [ `"`$topCommitQuality`" == `"BAD`" ] ; then "     >>  .\drive-bisect.sh
echo "        git bisect bad  > ../git-bisect.log "             >> .\drive-bisect.sh
echo "    elif [ `"`$topCommitQuality`" == `"GOOD`" ] ; then "  >>  .\drive-bisect.sh 
echo "        git bisect good  > ../git-bisect.log "            >> .\drive-bisect.sh
echo "    else "                                                >> .\drive-bisect.sh
echo "        git bisect skip > ../git-bisect.log "             >> .\drive-bisect.sh
echo "    fi "                                                  >> .\drive-bisect.sh
echo "    git log | head -1 > ../git-bisect-commit.log"  >> .\drive-bisect.sh
echo "    cd .. "                                        >> .\drive-bisect.sh
echo "fi"                                                >> .\drive-bisect.sh

cmd /c  "bin\dos2unix.exe -q drive-bisect.sh > nul 2>&1"
SendFileToVM         $server_VM_ip $sshKey ./const.sh          "const.sh" $true
SendFileToVM         $server_VM_ip $sshKey ./drive-bisect.sh   "drive-bisect.sh" $true
Write-Host "INFO: Running drive-bisect.sh on VM $server_VM_ip ... "
SendCommandToVM      $server_VM_ip $sshKey "chmod 755 *.sh && ./drive-bisect.sh"

WaitVMState $server_VM_ip $sshKey "INIT_FINISHED" 

Checkpoint-VM -Name $server_VM_Name -ComputerName $server_Host_ip -SnapshotName $linux_next_base_checkpoint -Confirm:$False
Checkpoint-VM -Name $client_VM_Name -ComputerName $client_Host_ip -SnapshotName $linux_next_base_checkpoint -Confirm:$False

############################################
# Find a bisect commit id
# and then test it: good, or bad?
############################################
$runid = 1
while ($true)
{
    $logid = ("{0:00}" -f $runid ) 
	Write-Host "------------------------------[STEP $logid]------------------------------"
	
	############################################
    # cleanup the vm /boot directory: remove previous initrd and vmlinuz to save disk space on /boot
	############################################
    SendCommandToVM $server_VM_ip $sshKey "rm -rf /boot/initrd.img* /boot/vmlinuz* /root/linux-image-*.deb"
    SendCommandToVM $client_VM_ip $sshKey "rm -rf /boot/initrd.img* /boot/vmlinuz* /root/linux-image-*.deb"    
    
	############################################
    # git bisect and build linux-next on server VM, 
	# then copy the kernel to client vm to install
	############################################
    $log = "bisect-and-build-" + $logid + ".log"
    echo "rm -rf ./teststate.sig "                         >  .\bisect-and-build.sh
    echo "echo BUILDTAG=$logid > build.tag"              >> .\bisect-and-build.sh
    echo "./drive-bisect.sh"                             >> .\bisect-and-build.sh
    echo "cd $linuxnextfolder"                                 >> .\bisect-and-build.sh
    echo "mv ../$distro_build_script ."                  >> .\bisect-and-build.sh
    echo "./$distro_build_script > ../$log"              >> .\bisect-and-build.sh
    echo "echo BUILD_FINISHED > ../teststate.sig"          >> .\bisect-and-build.sh
    echo "scp ../linux-image*.deb root@$client_VM_ip`: " >> .\bisect-and-build.sh
        
    SendFileToVM 	$server_VM_ip $sshKey ./const.sh              "const.sh" $true
    SendFileToVM 	$server_VM_ip $sshKey $distro_build_script  $distro_build_script $true
    SendFileToVM 	$server_VM_ip $sshKey ./bisect-and-build.sh  "bisect-and-build.sh" $true
    SendCommandToVM $server_VM_ip $sshKey "chmod 755 *.sh && ./bisect-and-build.sh"
    WaitVMState 	$server_VM_ip $sshKey "BUILD_FINISHED" 
    
    GetFileFromVM 	$server_VM_ip $sshKey $log                         $($logid + "-SERVER-" + $log)
    GetFileFromVM 	$server_VM_ip $sshKey "git-bisect.log"             $($logid + "-SERVER-git-bisect.log")
    GetFileFromVM 	$server_VM_ip $sshKey "git-bisect-commit.log"     $($logid + "-SERVER-git-bisect-commit.log")

    $commitfile = (Get-Content $($logid+"-SERVER-git-bisect-commit.log") )
    $bisect_commit_id = $commitfile.Split(" ")[1];
    Write-Host "Commit id parsed by git bisect has been applied: $bisect_commit_id"
    type $($logid + "-SERVER-git-bisect.log" )
    if ( (Get-Content $($logid+"-SERVER-git-bisect.log")).Contains("is the first bad commit"))
    {
        Write-Host "************************************************************"
        Write-Host "FINISHED"
        break
    }
	
    ############################################
    # install the kernel on client VM
	############################################
    $log = "install-kernel" + $logid + ".log"
    echo "rm -rf ./teststate.sig "                         >  .\install-kernel.sh
    echo "mkdir linux-next "                              >> .\install-kernel.sh
    echo "cd linux-next "                                 >> .\install-kernel.sh
    echo "mv ../$distro_build_script ."                  >> .\install-kernel.sh
    echo "./$distro_build_script > ../$log"              >> .\install-kernel.sh
    echo "echo BUILD_FINISHED > ../teststate.sig"          >> .\install-kernel.sh
    
    SendFileToVM 	$client_VM_ip $sshKey $distro_build_script  $distro_build_script $true
    SendFileToVM 	$client_VM_ip $sshKey ./install-kernel.sh   "install-kernel.sh" $true
    SendCommandToVM $client_VM_ip $sshKey "chmod 755 *.sh && ./install-kernel.sh"    
    WaitVMState 	$client_VM_ip $sshKey "BUILD_FINISHED" 
    
    GetFileFromVM 	$client_VM_ip $sshKey $log  $($logid + "-CLIENT-" + $log)
    
	############################################
    # kernel ready, make a checkpoint for debug purpose
	############################################
    Checkpoint-VM -Name $server_VM_Name -ComputerName $server_Host_ip -SnapshotName $($linux_next_base_checkpoint+$logid) -Confirm:$False
    Checkpoint-VM -Name $client_VM_Name -ComputerName $client_Host_ip -SnapshotName $($linux_next_base_checkpoint+$logid) -Confirm:$False
    
	############################################
    # restart the server and client VMs to boot from new kernel
	############################################
    SendCommandToVM $server_VM_ip $sshKey "init 6"
    SendCommandToVM $client_VM_ip $sshKey "init 6"

	############################################
    # is this kernel good to bootup?
	############################################
    $newKernelUp = $false
    $newKernelUp = WaitVMState $server_VM_ip $sshKey "BOOT_UP" 
    if ($newKernelUp -eq $true)
    {
        $currentKernelVersion = CheckVmKernelVersion $server_VM_ip $sshKey
        if ( -not $currentKernelVersion[-2].Contains( $("lisperfregression" + $logid)) )
        {
            $newKernelUp = $false
        }
    }
    
    if ($newKernelUp -eq $true)
    {
        $newKernelUp = WaitVMState $client_VM_ip $sshKey "BOOT_UP" 
        if ($newKernelUp -eq $true)
        {
            $currentKernelVersion = CheckVmKernelVersion $client_VM_ip $sshKey
            if ( -not $currentKernelVersion[-2].Contains( $("lisperfregression" + $logid)) )
            {
                $newKernelUp = $false
            }
        }
    }
    
	############################################
    # revert to previous checkpoint if current build cannot bootup
	############################################
    if ($newKernelUp -eq $false)
    {
        Write-Host "Commit id: $bisect_commit_id cannot be tested because the kernel cannot bootup" -ForegroundColor Red
        echo "topCommitQuality=SKIP"               >  .\const.sh

        InitVmUp $server_VM_Name $server_Host_ip $($linux_next_base_checkpoint+$logid)
        InitVmUp $client_VM_Name $client_Host_ip $($linux_next_base_checkpoint+$logid)
		$runid ++
        continue
    }

	############################################
    # Test this commit
	############################################
	# source the benchmark specific script
	# this script should have defined the function: RunBenchmarking()
	# and return a bool value to indicate the result is good ($true) or bad ($false)
	. .\$benchmark_script
	
	$returnObjs = RunBenchmarking $logid $bisect_commit_id
	$totalReturns = $returnObjs.Count
	Write-Host "The return values from benchmarking :"
	Write-Host $returnObjs
	$result_is_good = $returnObjs[$totalReturns-1]

	############################################
	# is this commit tested good?
	############################################
    if ($result_is_good -eq $true) 
    {
        $lastKnownGoodcommit = $bisect_commit_id
        Write-Host "Commit id: $bisect_commit_id is GOOD" -ForegroundColor Green
        echo "topCommitQuality=GOOD"	>  .\const.sh
    }
    else 
    {
        $lastKnownBadcommit = $bisect_commit_id
        Write-Host "Commit id: $bisect_commit_id is BAD" -ForegroundColor Yellow
        echo "topCommitQuality=BAD"		>  .\const.sh
    }
	
	$runid ++
}
