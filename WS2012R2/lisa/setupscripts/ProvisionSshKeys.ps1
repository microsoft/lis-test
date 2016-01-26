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
    Provision SSH keys in a Linux VM.

.Description
    This setup script will Provision SSH keys in a Linux VM, and
    make sure the the atd and dos2unix packages are installed.
    The LISA test framework uses SSH to communicate with the VM.
    LISA use SSH keys rather than password.  In addition to using
    SSH keys, LISA requires the dos2unix package and the atd
    service to run test jobs on the Linux VM.

    This script assumes the VM was created with a SSH server
    installed, the ssh server is configured to start on boot, and that
    root logins are enabled.  To find the specified SSH keys, this
    scripts also assumes it is being run from the lis-test\WS2012R2\lisa
    directory where the relative directory path .\SSH contains the public
    key, and the associated private key that has been converted to a Putty
    Private Key (.ppk).

    In addition to provisioning the SSH keys, this script will ensure
    the atd and dos2unix packages are installed.  Additional provisioning
    tasks can be performed by creating a test case that runs the
    provisionLinuxForLisa.sh test case script.  A sample test case
    definition that runs this setup script and the provisionLinuxForLisa.sh
    test case script would similar to the following definition:

    <test>
        <testName>ProvisionVmForLisa</testName>
        <testScript>provisionLinuxForLisa.sh</testScript>
        <setupScript>setupScripts\ProvisionSshKeys.ps1</setupScript>
        <files>remote-scripts\ica\provisionLinuxForLisa.sh</files>
        <timeout>1800</timeout>
        <onError>Abort</onError>
        <noReboot>False</noReboot>
        <testparams>
            <param>TC_COVERED=Provisioning</param>
            <param>publicKey=demo_id_rsa.pub</param>
        </testparams>
    </test>

    This setup script needs to know the root password for the VM so SSH
    can be used to copy SSH keys to the VM.  The script assumes a default root
    password of 'password'.  To specify a different password, include a
    testParameter of 'rootpassword'  The rootpassword testParameter can be
    specified in either the test case definition, or in the VM definition.
    A typical VM definition in the .xml file might look like the following:

    <VMs>        
	    <vm>
            <hvServer>localhost</hvServer>
            <vmName>VM_NAME</vmName>
            <os>Linux</os>
            <ipv4></ipv4>
            <sshKey>PVT.ppk</sshKey>
            <suite>ProvisionVM</suite>
            <testParams>
                <param>rootpassword=MyRootPassword</param>
            </testParams>
        </vm>
    </VMs>

    Note:  If your password uses the $ character, you will need to use the
    PowerShell escape character.  This is the back tic (same key as the 
    tilda ~).  e.g.  <param>rootpassword=PA`$`$Word</param>

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
    This setup script does not use any setup scripts.

#>


param ([String] $vmName, [String] $hvServer, [String] $testParams)


#######################################################################
#
# GetLinuxDsitro()
#
#######################################################################
function GetLinuxDistro([String] $ipv4, [String] $password)
{
    if (-not $ipv4)
    {
        return $null
    }

    if (-not $password)
    {
        return $null
    }

    $distro = bin\plink -pw "${password}" root@${ipv4} "grep -hs 'Ubuntu\|SUSE\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux\|Oracle' /etc/{issue,*release,*version}"
    if (-not $distro)
    {
        return $null
    }

    $linuxDistro = "undefined"

    switch -wildcard ($distro)
    {
        "*Ubuntu*"  {  $linuxDistro = "Ubuntu"
                       break
                    }
        "*CentOS*"  {  $linuxDistro = "CentOS"
                       break  
                    }
        "*Fedora*"  {  $linuxDistro = "Fedora"
                       break
                    }
        "*SUSE*"    {  $linuxDistro = "SUSE"
                       break
                    }
        "*Debian*"  {  $LinuxDistro = "Debian"
                       break
                    }
        "*Red Hat Enterprise Linux Server 7.*" {  $linuxDistro = "RedHat7"
                       break
                    }
        "*Red Hat Enterprise Linux Server 6.*" {  $linuxDistro = "RedHat6"
                       break
                    }
        "*Oracle*" {  $linuxDistro = "Oracle"
                       break
                    }
        default     {  $linuxDistro = "Unknown"
                       break
                    }
    }

    return ${linuxDistro}
}


#######################################################################
#
# InstallPackagesRequiredByLisa()
#
#######################################################################
function InstallPackagesRequiredByLisa([String] $ipv4, [String] $password)
{
    $distro = GetLinuxDistro $ipv4 "${password}"
    switch -regex ($distro)
    {
        CentOS   { $cmd = "yum -y install dos2unix at"                        }
        RedHat6   { $cmd = "yum -y install dos2unix at"                        }
        RedHat7   { $cmd = "yum -y install dos2unix at"                        }
        Oracle   { $cmd = "yum -y install dos2unix at"                        }
        SUSE     { $cmd = "zypper --non-interactive install dos2unix at"      }
        Ubuntu   { $cmd = "apt-get -y install dos2unix at"                    }
        default  { Throw "Error: Unable to determine the VMs OS distribution" }
    }

    $process = Start-Process bin\plink.exe -ArgumentList "-l root -pw ${password} ${vmIPv4} ${cmd}" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
        Throw "Error: Unable to install dos2unix and/or at packages on the VM"
    }

    switch -regex ($distro)
    {
        Ubuntu { $cmd = "update-rc.d atd enable && update-rc.d atd enable" }
        Oracle { $cmd = "chkconfig atd on" }
        RedHat6 { $cmd = "chkconfig atd on" }
        default { $cmd = "systemctl enable atd.service" }
    }

    $process = Start-Process bin\plink.exe -ArgumentList " -l root -pw ${password} ${vmIPv4} $cmd" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
        Throw "Error: Unable to enable the atd service"
    }

    #
    # For SLES, also disable the PackageKit service
    #
    if ($distro -eq "SUSE")
    {
        $process = Start-Process bin\plink.exe -ArgumentList " -l root -pw ${password} ${vmIPv4} systemctl disable packagekit.service" -PassThru -NoNewWindow -Wait

    }
}


#######################################################################
#
# Main script body
#
#######################################################################

try
{
    #
    # Make sure the required arguments were passed
    #
    if (-not $vmName)
    {
        Throw "Error: no VMName was specified"
    }

    if (-not $hvServer)
    {
        Throw "Error: No hvServer was specified"
    }

    if (-not $testParams)
    {
        Throw "Error: No test parameters specified"
    }

    #
    # Display the test parameters so they are captured in the log file
    #
    "TestParams : '${testParams}'"

    #
    # Parse the test parameters
    #
    $rootDir    = $null
    $publicKey  = "id_rsa.pub"
    $privateKey = $null
    $tcCovered  = "undefined"
    $password   = "password"

    $params = $testParams.Split(";")
    foreach ($p in $params)
    {
        $fields = $p.Split("=")
        switch ($fields[0].Trim())
        {
        "publicKey"    { $publicKey = $fields[1].Trim() }
        "rootdir"      { $rootDir   = $fields[1].Trim() }
        "TC_COVERED"   { $tcCovered = $fields[1].Trim() }
        "rootpassword" { $password  = $fields[1].Trim() }
        default        {}       
        }
    }

    if (-not $rootDir)
    {
        "Warn : no rootdir was specified"
    }
    else
    {
        if ( (Test-Path -Path "${rootDir}") )
        {
            cd $rootDir
        }
        else
        {
            "Warn : rootdir '${rootDir}' does not exist"
        }
    }

    #
    # Cleanup any summary.log left behind by a previous test run
    #
    $summaryLog  = "${vmName}_summary.log"
    Del $summaryLog -ErrorAction SilentlyContinue
    echo "Covers : ${tcCovered}" >> $summaryLog

    . .\setupscripts\TCUtils.ps1

    #
    # Verify the VMs exist, and the public SSH key
    #
    $vmObj = Get-VM -Name "${vmName}" -ComputerName "${hvServer}" -ErrorAction SilentlyContinue
    if ($null -eq $vmObj)
    {
        Throw "Error: The VM '$vmName' on server '$hvServer' does not exist"
    }

    if (-not (Test-Path "ssh\${publicKey}"))
    {
        Throw "Error: The public SSH key 'ssh\${publicKey}' does not exist for VM '$($vm.vmName)'"
    }

    #
    # Start the VM.
    #
    "Info : Starting the VM '${vmName}'"
    Start-VM -Name "${vmName}" -ComputerName "${hvServer}" -ErrorAction SilentlyContinue
    if (-not $?)
    {
        Throw "Error: Unable to start VM '${vmName}' on server '${hvServer}'"
    }

    #
    # Wait for the VM to start SSH
    #
    "Info : Determining VMs IP address"
    $timeout = 300
    while ($timeout -gt 0)
    {
        $vmIPv4 = GetIPv4 $vmName $hvServer
        if ($vmIPv4 -ne $null)
        {
            break
        }
        
        Start-Sleep -Seconds 10
        $timeout -= 10
    }

    if ($timeout -le 0)
    {
        Throw "Error: Unable to determine the IPv4 address of VM '${vmName}'"
    }

    #
    # Sleep a few seconds to give the OS time to finish initializing
    #
    $sleepTime = 10
    "Info : Sleeping for ${sleepTime} seconds to allow the VMs OS to finish starting up"
    Start-Sleep $sleepTime

    #
    # First, send a command to the VM to eat any prompt for the server key
    #
    echo "y" | bin\plink.exe -pw ${password} root@${vmIPv4} "hostname"

    #
    # If needed, create the .ssh directory on the VM, then 
    # push the SSH keys to the VM and create the authorized_keys
    # file.
    #
    "Info : Create the .ssh directory"
    $process = Start-Process bin\plink.exe -ArgumentList "-l root -pw ${password} ${vmIPv4} if [ ! -e ~/.ssh ]; then mkdir ~/.ssh; fi" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
        Throw "Error: Unable to create the .ssh directory on the VM"
    }

    "Info : Copy the ssh\${publicKey} to the VM"
    $process = Start-Process bin\pscp.exe -ArgumentList "-l root -pw ${password} ssh\${publicKey} ${vmIPv4}:.ssh/" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
        Throw "Error: Unable to copy sshKey '${publicKey}' to the VM"
    }

    "Info : chmod 600 .ssh/${publicKey}"
    $process = Start-Process bin\plink.exe -ArgumentList " -l root -pw ${password} ${vmIPv4} chmod 600 ~/.ssh/$publicKey" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
        Throw "Error: Unable to chmod 600 ~/.ssh/${pubKey}"
    }

    "info : Add public key to the .ssh/authorized_keys"
    $process = Start-Process bin\plink.exe -ArgumentList " -l root -pw ${password} ${vmIPv4} cat ~/.ssh/$publicKey >> ~/.ssh/authorized_keys" -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0)
    {
        Throw "Error: Unable to add public key to ~/.ssh/authorized_keys"
    }

    #
    # Install the dos2unix and at packages
    #
    "Info : Install packages required by LISA"
    InstallPackagesRequiredByLisa $vmIPv4 "${password}"

    #
    # Shutdown the VM
    #
    "Info : Stopping the VM"
    Stop-VM -Name "${vmName}" -ComputerName "${hvServer}" -Force -ErrorAction SilentlyContinue
    if (-not $?)
    {
        #
        # The stop failed, try to turnoff the VM
        #
        echo "Step 13" >> ~/nick.log
        Stop-VM -Name "${vmName}" -ComputerName "${hvServer}" -Force -TurnOff -ErrorAction SilentlyContinue
        if (-not $?)
        {
            Throw "Error: Unable to turnoff VM '${vmName}' on server ${hvServer}"
        }
    }
}
catch
{
    $_.Exception.Message
    "Error: Provisioning failed"

    $vmObj = Get-VM -Name "${vmName}" -ComputerName "${hvServer}"
    if ($vmObj.State -ne "Off")
    {
        Stop-VM -Name "${vmName}" -ComputerName "${hvServer}" -Force -TurnOff -ErrorAction SilentlyContinue
    }
    return $False
}

"Info : Setup script completed"

return $True
