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
    Run the Hot Add Remove NIC test case.

.Description
    This test script will hot add a synthetic NIC to a running Gen 2 VM.

    The logic of the script is:
        Process the test parameters.
        Ensure required test parameters were provided.
        Ensure the target VM exists and is a Gen 2 VM
        Ensure the VM has a single NIC
        Hot add a NIC with the name "Hot Add NIC" rather than the default
            name of "Network Adapter"
        Run the NET_VerifyHotAddMultiNIC.sh on the VM.  The script does the following
            Verify the input parameter is either "added" or "removed"
            if "added"
                Verify there are two eth devices.
                Bring eth1 online and acquire a DHCP address
            if "removed"
                Verify this is only one eth device.
        Hot remove the NIC 
        Check VM log for errors 

    A sample LISA test case definition would look similar to the following:

    <test>
        <testName>HotAddRemoveNIC</name>
        <setupScript>
            <file>setupscripts\RevertSnapshot.ps1</file>
        </setupScript>
        <testScript>setupscripts\NET_HotAddRemoveNIC.ps1</testScript>
        <files>remote-scripts\ica\NET_VerifyHotAddMultiNIC.sh</files>
        <onError>Continue</onError>
        <timeout>1800</timeout>
        <testParams>
            <param>TC_Covered=NET-17</param>
            <param>Switch_Name=External</param>
        </testParams>
    </test>
#>

param( [String] $vmName, [String] $hvServer, [String] $testParams )

$HOT_ADD_NAME = "Hot Add NIC"

########################################################################
#
# Main script body
#
########################################################################
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
    $switchName = "ExternalNet"
    $testLogDir = $null
    $nicName    = $HOT_ADD_NAME

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
        "NIC_Name"      { $nicName     = $val }
        "Switch_Name"   { $switchName  = $val }
        default         { continue }
        }
    }

    #
    # Display the test parameters in the log file
    #
    "Info : Test parameters"
    "         sshKey     = ${sshKey}"
    "         ipv4       = ${ipv4}"
    "         rootDir    = ${rootDir}"
    "         tcCovered  = ${tcCovered}"
    "         testLogDir = ${testLogDir}"
    "         nicName    = ${nicName}"
    "         SwitchName = ${switchName}"

    #
    # Change the working directory to where we should be
    #
    if (-not $rootDir)
    {
        Throw "Error: The roodDir parameter was not provided by LISA"
    }

    if (-not (Test-Path $rootDir))
    {
        Throw "Error: The directory `"${rootDir}`" does not exist"
    }

    "Info : Changing directory to '${rootDir}'"
    cd $rootDir

    #
    # Make sure the required testParams were found
    #
    "Info : Verify required test parameters were provided"
    if (-not $sshKey)
    {
        Throw "Error: testParams is missing the sshKey parameter"
    }

    if (-not (Test-Path ssh\${sshKey}))
    {
        Throw "Error: The SSH key 'ssh\${sshKey}' does not exist"
    }

    if (-not $ipv4)
    {
        Throw "Error: The ipv4 parameter was not provided by LISA"
    }

    #
    # Delete any summary.log from a previous test run, then create a new file
    #
    $summaryLog = "${vmName}_summary.log"
    del $summaryLog -ErrorAction SilentlyContinue
    "Info : Covers ${tcCovered}" >> $summaryLog

    #
    # Source the utility functions so we have access to them
    #
    . .\setupscripts\TCUtils.ps1

    #
    # Eat any Putty prompts asking to save the server key
    #
    echo y | bin\plink.exe -i ssh\${sshKey} root@${ipv4} exit

    #
    # Verify the target VM exists, and that it is a Gen2 VM
    #
    "Info : Verify the SUT VM exists"
    $vm = Get-VM -Name $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to find VM '${vmName}' on server '${hvServer}'"
    }

    if ($vm.Generation -ne 2)
    {
        Write-Output "Info: This test requires a Gen 2 VM. VM '${vmName}' is not a Gen2 VM" | Tee-Object -Append -file $summaryLog
        return $Skipped
    }

    #
    # Verify Windows Server version
    #
    $osInfo = GetHostBuildNumber $hvServer
    if (-not $osInfo)
    {
        "Error: Unable to collect Operating System information"
        return $False
    }
    if ($osInfo -le 9600)
    {
        Write-Output "Info: This test requires Windows Server 2016 or higher" | Tee-Object -Append -file $summaryLog
        return $Skipped
    }
    
    #
    # Verify the target VM does not have a Hot Add NIC.  If it does, then assume
    # there is a test configuration or setup issue, and fail the test.
    #
    # Note: When adding a synthetic NIC, the default name will be "Network Adapter".
    #       When this script adds a NIC, the name "Hot Add NIC" will be assigned
    #       to the hot added NIC rather than the default name.  This allows us to
    #       check that there are no synthetic NICs with the name "Hot Add NIC".
    #       It also makes it easy to remove the hot added NIC since we can find
    #       the hot added NIC by name.
    #
    "Info : Ensure the VM does not have a Synthetic NIC with the name '${nicName}'"
    $nics = Get-VMNetworkAdapter -vmName $vmName -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if ($?)
    {
        Throw "Error: VM '${vmName}' already has a NIC named '${nicName}'"
    }

    #
    # Hot Add a Synthetic NIC to the SUT VM.  Specify a NIC name of "Hot Add NIC".
    # This will make it easy to later identify the NIC to remove.
    #
    "Info : Hot add a synthetic NIC with a name of '${nicName}' using switch '${switchName}'"
    Add-VMNetworkAdapter -VMName $vmName -SwitchName "${switchName}" -Name "${nicName}" -ComputerName $hvServer #-ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to Hot Add NIC to VM '${vmName}' on server '${hvServer}'"
    }

    #
    # Run the NET_VerifyHotAddSyntheticNIC.sh on the SUT VM to verify the VM detected the hot add
    #
    "Info : Verify the OS on the SUT detected the NIC"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix NET_VerifyHotAddMultiNIC.sh 2>&1"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod 755 NET_VerifyHotAddMultiNIC.sh 2>&1"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./NET_VerifyHotAddMultiNIC.sh added 2>&1"
    if (-not $?)
    {
        Throw "Error: Unable to verify NIC was detected within the SUT VM '${vmName}'"
    }

    #
    # Display the output from NET_VerifyHotAddMultiNIC.sh so it is captured in the log file
    #
    "Info : Output from NET_VerifyHotAddMultiNIC.sh"
    $sts

    #
    # Hot Remove the Hot Add'ed synthetic NIC from the SUT VM
    #
    "Info : Hot remove the NIC"
    $nics = Get-VMNetworkAdapter -vmName "${vmName}" -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        #
        # Sanity check - this error should never occur
        #
        Throw "Error: VM '${vmName}' does not have a NIC named '${nicName}'"
    }

    if ($nics.Length -ne 1)
    {
        #
        # Sanity check - this error should never occur
        #
        Throw "Error: VM '${vmName}' has more than one Hot Added NIC"
    }

    #
    # Now Hot Remove the NIC
    #
    Remove-VMNetworkAdapter -VMName $vmName -Name "${nicName}" -ComputerName $hvServer -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to remove hot added NIC"
    }

    #
    # Run the NET_VerifyHotAddSyntheticNIC.sh on the SUT VM to verify the VM detected the hot remove
    #
    "Info : Verify the OS on the SUT detected the NIC was hot removed"
    $sts = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./NET_VerifyHotAddMultiNIC.sh removed 2>&1"
    if (-not $?)
    {
        "${sts}"
        Throw "Error: Unable to verify NIC was removed within the SUT VM '${vmName}'"
    }

    #
    # Display the output from NET_VerifyHotAddMultiNIC.sh so it is captured in the log file
    #
    "Info : Output from NET_VerifyHotAddMultiNIC.sh"
    $sts

    if ($sts -match "netvsc throwed errors"){
        Throw "Error: VM '${vmName}' reported that netvsc throwed errors"
    }
}
catch
{
    $msg = $_.Exception.Message
    "Error: ${msg}"
    "${msg}" >> $summaryLog
    return $False
}

#
# If we made it here, everything worked
#
"Info : Test completed successfully"

return $True