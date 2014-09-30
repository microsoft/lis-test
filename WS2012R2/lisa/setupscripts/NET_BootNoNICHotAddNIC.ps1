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
    Hot Add a NIC to a Gen2 VM that booted without a NIC.

.Description
    Test case for booting a Gen2 VM without a NIC, hot add a
    NIC, verify it works, then hot remove the NIC.

    Note: The Hot Add NIC feature is only supported on Gen 2 VMs.
          This test case requires a Gen 2 VM.

    The LISA test framework will boot the Linux VM (SUT) which is a Gen2 VM.
    Initially, the SUT has a NIC.  LISA will push files to the VM using SSH,
    and then pass control to this test script.  This script will do the
    following tasks:
      - Configure the root user for autologin.
      - Configure the NET_VerifyBootNoNIC.sh to autostart when the root
        user logs in.
      - Remove the NIC from the VM.
      - Stop the SUT VM.
      - Boot the VM.
        Note: because of the autologin and autostart configurations, rebooting
              the VM will login in the root user and start the script
              NET_VerifyBootNoNIC.sh running.
      - Wait for VM to create the HotAddTest KVP item.  The NET_VerifyBootNoNIC.sh
        will create the HotAddTest KVP item.
      - Hot Add a NIC to the VM.
        The NET_VerifyBootNoNIC.sh script running on the SUT is in a loop
        waiting for a eth device to appear.  Once the device appears, the
        NET_VerifyBootNoNIC.sh script will bring the new eth device up, then
        set the HotAddTest KVP item value to 'NICUp'
      - Wait for the VM to modify the HotAddTest KVP item value to: NICUp
      - Verify an IP address was assigned to the hot added NIC.
      - Hot remove the NIC
      - Wait for the VM to modify the HotAddTest KVP item value to: NoNICs.
        After NET_VerifyBootNoNIC.sh configured the new eth device, it entered
        a loop where it is looking for the eth device to be removed.  Once the
        eth device is removed, the NET_VerifyBootNoNIC.sh will set the
        HotAddTest KVP item value to 'NoNICs'
      - Verify the guest OS detected the hot remove.
      - Shutdown the VM
      - Apply the ICABase snapshot.  This will restore the original NIC.  This
        should result in DHCP assigning the original IP address back to the
        VMs NIC, which will allow LISA to continue communicating with the test VM.
      - Reboot the VM
      - Complete the test.
    Once this test script completes, the LISA test framework will collect 
    log files from the VM and then continue the test run

    The logic of the NET_VerifyBootNoNIC.sh script is:
      - Verify there are no eth devices on the system.
      - Create a Non-Intrinsic KVP item (pool 1) with the following
        properties:
            Key Name : HotAddTest
            Key Value: NoNICs
      - Loop waiting for the creation of a eth device.
      - Configure the new eth device so it receives an IP address via DHCP.
      - Verify the new eth device was assigned an IP address.
      - Modify the KVP HotAddTest item value to: NICUp.
      - Loop waiting for the eth device to go away.
      - Modify the KVP HotAddTest item value to NoNICs.

    A sample LISA test case definition would look similar to the following:

        <test>
            <testName>BootNoNicHotAddNic</testName>
            <testScript>SetupScripts\NET_BootNoNICHotAddNIC.ps1</testScript>
            <files>remote-scripts\ica\NET_VerifyBootNoNIC.sh,tools\KVP\kvp_client</files>
            <timeout>1800</timeout>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
            <testparams>
                <param>TC_COVERED=NET-??</param>
                <param>Switch_Name=ExternalNet</param>
            </testparams>
        </test>

.Example
    .\NET_BootNoNICHotAddNIC.ps1 -vmName "TestVM" -hvServer "localhost" -testParams "ipv4=192.168.1.100;sshKey=ir_rsa.ppk;SwitchName=ExternalNet;rootDir=C:\public;TC_COVERED=NET-12"

#>

param( [String] $vmName, [String] $hvServer, [String] $testParams )


#$SNAPSHOT_NAME = "HOT_ADD_TEST"
$KVP_KEY       = "HotAddTest"


#######################################################################
#
# ConfigureAutoStartOnVM
#
# Description:
#    Configure the root user to automatically login after the 
#    VM is booted.  Also configure a script to autostart when
#    the root user is logged in.
#
#######################################################################
function ConfigureAutoStartOnVM()
{
    $hotAddScript = "NET_VerifyBootNoNIC.sh"

    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ./${hotAddScript} 2>&1"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 ./${hotAddScript}"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 ./kvp_client"

    # 
    # Configure the root user for autologin 
    # 
    #
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "sed -i 's/DISPLAYMANAGER_AUTOLOGIN=\`"\`"/DISPLAYMANAGER_AUTOLOGIN=\`"root\`"/g' /etc/sysconfig/displaymanager"
  
    #
    # Configure NET_VerifyBootNoNIC.sh to start when the root user logs in
    # 
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo '#!/bin/bash' > /root/launchscript.sh"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo `"./${hotAddScript}`" >> /root/launchscript.sh"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 /root/launchscript.sh"

    #
    # Create the autostart file to run the NET_VerifyBootNoNIC.sh script on login
    #
    $AUTOSTART = "/root/.config/autostart/hotaddnic.desktop"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "mkdir /root/.config/autostart"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo '[Desktop Entry]'                 >  $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'X-SuSE-translate=true'           >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'GenericName=HotAddNicTest'       >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'Name=Hot Add NIC Test'           >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'Comment=Test Gen2 Hot Add NIC'   >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'TryExec=/root/launchscript.sh'   >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'Exec=/root/launchscript.sh'      >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'Icon=utilities-terminal'         >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'Type=Application'                >> $AUTOSTART"
    bin\plink.exe -i ssh\${sshKey} root@${ipv4} "echo 'StartupNotify=true'              >> $AUTOSTART"
}


########################################################################
#
# GetKVPItem()
#
# Description:
#    Return the value of the specified Non-Intrinsic KVP item.
#    Return null if the KVP item does not exist.
#
########################################################################
function GetKVPItem([String] $vm, [String] $server, [String] $keyName, [Switch] $Intrinsic)
{
    $vm = Get-WmiObject -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$vmName`'"
    if (-not $vm)
    {
        return $Null
    }

    $kvpEc = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
    if (-not $kvpEc)
    {
        return $Null
    }

    $kvpData = $Null

    if ($Intrinsic)
    {
        $kvpData = $KvpEc.GuestIntrinsicExchangeItems
    }
    else
    {
        $kvpData = $KvpEc.GuestExchangeItems
    }

    if ($kvpData -eq $Null)
    {
        return $Null
    }

    foreach ($dataItem in $kvpData)
    {
        $key = $null
        $value = $null
        $xmlData = [Xml] $dataItem
        
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name")
            {
                $key = $p.Value
            }

            if ($p.Name -eq "Data")
            {
                $value = $p.Value
            }
        }
        if ($key -eq $keyName)
        {
            return $value
        }
    }

    return $Null
}


########################################################################
#
# DoTest()
#
# Description:
#    This code runs in lock step with the KVP_VerifyBootNoNIC.sh script,
#    which is running on the Linux VM.  KVP values are used to keep this
#    script in sync with the Bash script on the VM.
#
#    Wait for the Bash script to create the HotAddTest KVP item.
#    Verify it is set to "NoNICs'
#    Hot add a NIC
#    Wait for the Bash script to modify the HotAddTest KVP value to 'NICUp'
#    Verify Hyper-V sees the IP addresses assigned to the hot added NIC.
#    Hot remove the NIC
#    Wait for the Bash script to modify the HotAddTest KVP value to 'NoNICs'
#
########################################################################
function DoTest()
{
    #
    # Wait for the guest to create the HotAddTest KVP item, with a value of 'NoNICs'
    #
    "Info : Waiting for the VM to create the HotAddTest KVP item"
    $tmo = 300
    $value = $null
    while ($tmo -gt 0)
    {
        $value = GetKvpItem $vmName $hvServer "${KVP_KEY}"
        if ($value -ne $null)
        {
            break
        }

        $tmo -= 10
        Start-Sleep -Seconds 10
    }

    if ($value -ne "NoNICs")
    {
        Throw "Error: The VM never reported 0 NICs found"
    }

    #
    # Hot Add a NIC
    #
    "Info : Hot add a synthetic NIC"
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $switchName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to Hot Add NIC to VM '${vmName}' on server '${hvServer}'"
    }

    #
    # Wait for the guest to modify the HotAddTest KVP item value to 'NICUp'
    #
    "Info : Waiting for the VM to set the HotAddTest KVP item to NICUp"
    $tmo = 300
    $value = $null
    while ($tmo -gt 0)
    {
        $value = GetKvpItem $vmName $hvServer "${KVP_KEY}"
        if ($value -eq "NICUp")
        {
            break
        }

        $tmo -= 10
        Start-Sleep -Seconds 10
    }

    if ($value -ne "NICUp")
    {
        Throw "Error: The VM never reported the NIC is up"
    }
    
    #
    # Verify the Hot Added NIC was assigned an IP address
    #
    $nic = Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $nic)
    {
        Throw "Error: Unable to create Network Adapter object for VM '${vmName}'"
    }

    if ($nic.IPAddresses.length -lt 2)
    {
        # To Do - check that one of the IP address matches an IPv4 syntax
        Throw "Error: insufficient IP addresses reported by test VM"
    }

    #
    # Hot Remove the NIC
    #
    Remove-VMNetworkAdapter -VMName $vmName -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to remove hot added NIC"
    }

    #
    # Wait for the guest to modify the HotAddTest KVP item value to 'NoNICs'
    #
    "Info : Waiting for the VM to set the HotAddTest KVP item to 'NoNICs'"
    $tmo = 300
    $value = $null
    while ($tmo -gt 0)
    {
        $value = GetKvpItem $vmName $hvServer "${KVP_KEY}"
        if ($value -eq "NoNICs")
        {
            break
        }

        $tmo -= 10
        Start-Sleep -Seconds 10
    }

    if ($value -ne "NoNICs")
    {
        Throw "Error: The VM never detected the Hot Remove of the NIC"
    }
}


########################################################################
#
# Main script body
#
########################################################################

#
# Use a common error handler for all errors
#
try
{
    #
    # Make sure all command line arguments were provided
    #
    if (-not $vmName)
    {
        Throw "Error: vmName argument is null"
    }

    if (-not $hvServer)
    {
        Throw "Error: hvServer argument is null"
    }

    if (-not $testParams)
    {
        Throw "Error: testParams argument is null"
    }

    #
    # Parse the testParams string
    #
    "Info : Parsing test parameters"
    $sshKey     = $null
    $ipv4       = $null
    $rootDir    = $null
    $tcCovered  = "NET-??"
    $testLogDir = $null
    $switchName = $null

    $params = $testParams.Split(";")
    foreach($p in $params)
    {
        $tokens = $p.Trim().Split("=")
        if ($tokens.Length -ne 2)
        {
            continue   # Just ignore the parameter
        }
    
        $val = $tokens[1].Trim()
    
        switch($tokens[0].Trim().ToLower())
        {
        "ipv4"          { $ipv4        = $val }
        "sshkey"        { $sshKey      = $val }
        "rootdir"       { $rootDir     = $val }
        "TC_COVERED"    { $tcCovered   = $val }
        "TestLogDir"    { $testLogDir  = $val }
        "Switch_Name"   { $switchName  = $val }
        default         { continue }
        }
    }

    #
    # Display the test parameters in the log file
    #
    "Info : Test parameters"
    "         sshKey      = ${sshKey}"
    "         ipv4        = ${ipv4}"
    "         rootDir     = ${rootDir}"
    "         tcCovered   = ${tcCovered}"
    "         testLogDir  = ${testLogDir}"
    "         switch_Name = ${switchName}"

    #
    # Change the working directory to where we should be
    #
    "Info : Changing directory to ${rootDir}"
    if (-not $rootDir)
    {
        Throw "Error: The roodDir parameter was not provided by LISA"
    }

    if (-not (Test-Path $rootDir))
    {
        Throw "Error: The directory `"${rootDir}`" does not exist"
    }

    cd $rootDir

    #
    # Make sure the required testParams were found
    #
    "Info : Verify required test parameters were provided"
    if (-not $ipv4)
    {
        Throw "Error: The ipv4 parameter was not provided by LISA"
    }

    if (-not $sshKey)
    {
        Throw "Error: testParams is missing the sshKey parameter"
    }

    if (-not (Test-Path ssh\${sshKey}))
    {
        Throw "Error: The SSH key 'ssh\${sshKey}' does not exist"
    }

    "Info : Verify required test parameters were provided"
    if (-not $switchName)
    {
        Throw "Error: The Switch_Name test parameter was not provided"
    }

    #
    # Delete any summary.log from a previous test run, then create a new file
    #
    "Info : Cleanup any old summary.log file"
    $summaryLog = "${vmName}_summary.log"
    del $summaryLog -ErrorAction SilentlyContinue
    "Info : Covers ${tcCovered}" >> $summaryLog

    #
    # Source the utility functions so we have access to them
    #
    . .\setupscripts\TCUtils.ps1

    #
    # Eat any Putty prompts to save the server key
    #
    echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} exit

    #
    # Verify the target VM exists, and that it is a Gen 2 VM
    #
    "Info : Verify the SUT VM '${vmName}' exists"
    $vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to find VM '${vmName}' on server '${hvServer}'"
    }

    if ($vm.Generation -ne 2)
    {
        Throw "Error: This test requires a Gen 2 VM.  VM '${vmName}' is not a Gen2 VM"
    }

    #
    # Verify the target VM has a single NIC - Standard LISA test configuration
    #
    "Info : Verify the VM has a single NIC"
    $nics = Get-VMNetworkAdapter -vmName $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: VM '${vmName}' does not have a single NIC"
    }

    if ($nics.Length -ne 1)
    {
        Throw "Error: VM '${vmName}' has more than one NIC"
    }

    #
    # Configure the root user to be logged automatically when the VM boots,
    # and configure the NET_VerifyBootNoNIC.sh script to be run automatically
    # when the root user logs in.
    #
    ConfigureAutoStartOnVM

    #
    # Stop the VM
    #
    "Info : Stopping the VM"
    Stop-VM -Name "${vmName}" -ComputerName $hvServer -Force -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to stop VM to allow removal of original NIC"
    }

    #
    # Take snapshot and name snapshot HOT_ADD_TEST
    #
    #"Info : Creating ${SNAPSHOT_NAME} snapshot"
    #Checkpoint-VM -Name "${vmName}" -SnapshotName "${SNAPSHOT_NAME}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    #if (-not $?)
    #{
    #    Throw "Error: Unable to create ${SNAPSHOT_NAME} snapshot"
    #}

    #
    # Remove the original NIC
    #
    "Info : Remove the original NIC from the VM"
    Remove-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to Hot Remove NIC"
    }

    "Info : Verify the VM does not have any NICs"
    $nics = Get-VMNetworkAdapter -vmName $vmName -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: VM '${vmName}' still has a NIC after Hot Remove"
    }

    #
    # Boot the VM
    #
    "Info : Starting the VM"
    Start-VM -Name "${vmName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to start VM after removing original NIC"
    }

    #
    # Run the Boot with No NIC test
    # Note: DoTest will throw an error if the test fails, so ther is no
    #       explicit check for success.
    #
    DoTest

    #
    # Shutdown the VM
    #
    "Info : Stopping the VM again"
    Stop-VM -Name "${vmName}" -ComputerName $hvServer -Force -TurnOff -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to stop VM to allow removal of original NIC"
    }

    #
    # Apply the snapshot, which will restore the original NIC/MAC.  This
    # should allow DHCP to assign the original IP address.  This is required
    # for LISA to continue communicating with the VM.
    #
    Restore-VMSnapshot -VMName "${vmName}" -Name "ICABase" -ComputerName $hvServer -Confirm:$False -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to apply the '${SNAPSHOT_NAME}' snapshot"
    }

    #
    # Boot the VM so it is running - LISA will want the VM running
    #
    "Info : Starting the VM after applying the snapshot"
    Start-VM -Name "${vmName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to start VM after removing original NIC"
    }

    #
    # Wait for the guest OS to start the SSH daemon
    #
    $sts = WaitForVMToStartSSH $ipv4 300
    if (-not $sts)
    {
        Throw "Error: SSH start not detected on SUT after Hot Add/Remove tests"
    }
}
catch
{
    "Error: Test failed"
    $msg = $_.Exception.Message
    "${msg}"
    "${msg}" >> $summaryLog
    return $False
}

#
# If we made it here, everything worked
#
"Info : Test completed successfully"

return $True
