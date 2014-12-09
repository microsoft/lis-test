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
# validatexml.ps1  --  Validate XML config file
#
# Description:
#     This script validates the entries in the ica xml config file.
#
#
# History:
#   11-24-2009  nmeier  Created.
#
#   03-30-2010  nmeier  Added -checkhv switch to validate the
#                       hyper-v specific information.  Added
#                       function CheckHypervServer() to do the
#                       work.
#
#   03-31-2010  nmeier  Added -checkvm switch to validate the
#                       vm specific information.  This includes
#                       checking the VM IP address and SSH key.
#                      
#
#
########################################################################


#######################################################################
#
# Usage
#
# Description:
#     Display the usage (help) text.
#
#######################################################################
function Usage()
{
    write-host ""
    write-host "  This script validates the structure, the tags, and the"
    write-host "  data in an ICA .xml file."
    write-host ""
    write-host "  Usage:"
    write-host "    validatexml.ps1 xmlfile [-checkhv] [-checkvm] [-help]"
    write-host ""
    write-host "    xmlfile  : Required.  This is the filename of the .xml file to check."
    write-host ""
    write-host "    -checkhv : Optional.  Validate data specific to any hyper-v"
    write-host "                          servers identified in the .xml file."
    write-host ""
    write-host "    -checkvm : Optional.  Validate data specific to any virtual machine"
    write-host "                          specified in the .xml file."
    write-host "                          Note: These checks are time consuming since"
    write-host "                                the VM must be running.  If the VM is"
    write-host "                                not running, this check will start the"
    write-host "                                vm, perform the test, then stop the VM."
    write-host ""
    write-host "    -help    : Optional.  Displays this message.  If the -help switch"
    write-host "                          is specified on the command line, all other"
    write-host "                          data is ignored."
    write-host ""
}




#######################################################################
#
# DoGlobalChecks
#
# Description:
#     Check that required entries in the <global> section of the .xml
#     file are present.  Note that the actual values of these tags
#     are not validated.
#
#######################################################################
function DoGlobalChecks([XML] $xmlConfig)
{
    $retVal = 0

    #
    # Make sure the <config> section exists
    if (! $xmlConfig.config)
    {
        LogMsg 0 "Error: <config> section is missing."
        return 1
    }

    # Make sure the <global> section is defined.
    if (! $xmlConfig.config.global)
    {
        LogMsg 0 "Error: <config.global> section is missing."
        return 1
    }

    # Check the <logfileRootDir> property
    if (! $xmlConfig.config.global.logfileRootDir)
    {
        LogMsg 0 "Error: <config.global.logfileRootDir> is missing."
        $retVal = 1
    }
    
    # Check <defaultSnapshot> property
    if (! $xmlConfig.config.global.defaultSnapshot)
    {
        LogMsg 0 "Error: <config.global.defaultSnapshot> is missing."
        $retVal = 1
    }
    
    # Check the <email> section
    if (! $xmlConfig.config.global.email)
    {
        LogMsg 0 "Error: <config.global.email> section is missing."
        $retVal = 1
    }

    # Check the <emailSender> tag
    if (! $xmlConfig.config.global.email.sender)
    {
        LogMsg 0 "Error: <config.global.email.sender> is missing."
        $retVal = 1
    }

    # Check the <emailSubject> tag
    if (! $xmlConfig.config.global.email.subject)
    {
        LogMsg 0 "Error: <config.global.email.subject> is missing."
        $retVal = 1
    }

    # Check the <smtpServer> tag
    if (! $xmlConfig.config.global.email.smtpServer)
    {
        LogMsg 0 "Error: <config.global.email.smtpServer> is missing."
        $retVal = 1
    }

    # Check the <recipients> section>
    if (! $xmlConfig.config.global.email.recipients)
    {
        LogMsg 0 "Error: <config.global.email.recipients> section is missing."
        $retVal = 1
    }
    else
    {
        if (! $xmlConfig.config.global.email.recipients.to)
        {
            LogMsg 0 "Error: There are no email recipeients defined <recipients.to>"
            $retVal = 1
        }
    }
    
    # Check for at least one recipient
    
    return $retVal
}


#######################################################################
#
#######################################################################
function TestCaseExists( $name, $xmlData)
{
    $retVal = $false
    
    if ($xmlData.config.testCases.test)
    {
        foreach ($t in $xmlData.config.testCases.test)
        {
            if ($t.testName -eq $name)
            {
                $retVal = $true
                break
            }
        }
    }
    
    return $retVal
}


#######################################################################
#
# DoSuiteChecks
#
#######################################################################
function DoSuiteChecks ([XML] $xmlConfig)
{
    $retVal = 0

    # Check the <testSuites> tag
    if (! $xmlConfig.config.testSuites)
    {
        LogMsg 0 "Error: The <testSuites> tag is missing"
        $retVal = 1
    }
    
    # Check the <suite>
    if (! $xmlConfig.config.testSuites.suite)
    {
        LogMsg 0 "Error: There are no test suites defined under the <testSuites> tag"
        $retVal = 1
    }
    
    # For each suite, check the suiteName and suiteTest tags
    foreach ($s in $xmlConfig.config.testSuites.suite)
    {
        # Check for the suiteName tag
        if (! $s.suiteName)
        {
            LogMsg 0 "Error: A test suite is missing the <suiteName> tag"
            $retVal = 1
        }
        
        if (! $s.suiteTests)
        {
            LogMsg 0 "Error: Suite '$($s.suiteName)' is missing the <suiteTests> section"
            $retVal = 1
        }

        if (! $s.suiteTests.suiteTest)
        {
            LogMsg 0 "Error: Suite '$($s.suiteName)' does not have any <suiteTest> defined"
            $retVal = 1
        }
        else
        {
            # Make sure each test the suite references is defined in the <testCase> section
            foreach ($st in $s.suiteTests.suiteTest)
            {
                if (! (TestCaseExists $st $xmlConfig) )
                {
                    LogMsg 0 "Error: Test suite $($s.suiteName) references test $($st), which is not a defined testCase"
                    $retVal = 1
                }
            }
        }
    }

    return $retVal
}


#######################################################################
#
# DoTestsChecks
#
# Description:
#     Check that <tests> section of the .xml exists, and that at
#     least one <test> is defined.  For each <test> present, validate
#     it's required tags are present.
#     Note that the actual values of these tags are not validated.
#
#######################################################################
function DoTestsChecks([XML] $xmlConfig)
{
    $retVal = 0

    # Check the <tests> tag
    if (! $xmlConfig.config.testCases)
    {
        LogMsg 0 "Error: <config.tests> section is missing."
        return 1
    }

    # Make sure at least one test section is defined
    if (! $xmlConfig.config.testCases.test)
    {
        LogMsg 0 "Error: there are no <config.tests.test> sections."
        return 1
    }

    # Check each test
    foreach($test in $xmlConfig.config.testCases.test)
    {
        $results = ValidateTest $test
        if (0 -ne $results)
        {
            $retVal = $results
        }
    }

    return $retVal
}


#######################################################################
#
# ValidateTest
#
# Description:
#     Make sure the required tags for a test are present.
#
#######################################################################
function ValidateTest($test)
{
    $retVal = 0

    # Check the <testname> tag
    if (! $test.testName)
    {
        LogMsg 0 "Warn : A test is missing the <testName> tag."
        $retval = 1
    }
    
    # Check the <testscript> tag
    if (! $test.testScript)
    {
        LogMsg 0 "Error: The test $($test.testName) is missing the <testScript> tag."
        $retVal = 1
    }

    # Check the <timeout> tag
    if (! $test.timeout)
    {
        LogMsg 0 "Error: The test $($test.testName) is missing the <timeout> tag."
        $retVal = 1
    }
    else
    {
        if (([int]$test.timeout -le 0) -or ([int]$test.timeout -gt 86400))
        {
            LogMsg 0 "Error: Timeout value for test $($test.testName)is invalid"
            LogMsg 0 "Error: The value must be greater than 0 and less than 86400 (24 hours)"
            $retVal = 1
        }
    }

    # Check the <files> tag
    #   This is a comma separated list of files that are pushed to the SUT
    if ($test.files)
    {
        $files = ($test.files).split(",")
        foreach ($file in $files)
        {
            if (! (test-path $file.Trim()) )
            {
                LogMsg 0 "Error: A file or directory for test '$($test.testName)' does not exist. File = $($file.Trim())"
                $retVal = 1
            }
        }
        # To Do: Make sure the file identified in the <testscript> tag is in the files list.
    }
    else
    {
        LogMsg 0 "Error: The test $($test.testName) is missing the <files> tag."
        $retVal = 1
    }

    # Check the setupScript and cleanupScript tags
    if ($test.setupScript)
    {
        # see if the script actually exists
        if (! (test-path $test.setupScript.Trim()))
        {
            LogMsg 0 "Error: The setupScript $($test.setupScript.Trim()) for test $($test.testName) does not exist"
            $retVal = 1
        }
    }
    
    if ($test.cleanupScript)
    {
        # see if the script actually exists
        if (! (test-path $test.cleanupScript.Trim()))
        {
            LogMsg 0 "Error: The cleanupScript $($test.cleanupScript.Trim()) for test $($test.testName) does not exist"
            $retVal = 1
        }
    }
    
    return $retVal
}


#######################################################################
#
# DoVMsChecks
#
# Description:
#     Make sure at least one VM is defined.  For each VM, check that
#     the required tags for a VM have been specified.
#
#######################################################################
function DoVMsChecks([XML] $xmlConfig)
{
    $retVal = 0

    # Make sure the <VMs> section is defined.
    if (! $xmlConfig.config.VMs)
    {
        LogMsg 0 "Error: <config><VMs> section is missing."
        return 1
    }

    # Make sure at least one <vm> section is defined.
    if (! $xmlConfig.config.VMs.vm)
    {
        LogMsg 0 "Error: there are no virtual machines (The <config><VMs><vm> does not exist)."
        return 1
    }

    # Check each <vm>
    foreach($vm in $xmlConfig.config.VMs.vm)
    {
        $result = ValidateVM $vm $xmlConfig
        if (0 -ne $result)
        {
            $retVal = $result
        }
    }

    return $retVal
}


#######################################################################
#
# ValidateVM
#
# Description:
#     Make sure the required tags for a VM are present.
#
#######################################################################
function ValidateVM($vm, $xmlData)
{
    $retVal = 0

    # Check the <vmname> tag
    if (!$vm.vmName)
    {
        LogMsg 0 "Error: A <vm> is missing the <vmName> attribute."
        $retVal = 1
    }

    # Check the <hvserver> tag
    if (!$vm.hvServer)
    {
        LogMsg 0 "Error: The VM $($vm.vmName) is missing the <hvServer> tag."
        LogMsg 0 "Error: The <hvServer> attribute contains the name, or IP address, of the Hyper-V server hosting the VM."
        $retVal = 1
    }

    # Check the <ipv4> tag
    if (!$vm.ipv4)
    {
        LogMsg 0 "Error: The VM $($vm.vmName) is missing the <ipv4> attribute."
        LogMsg 0 "Error: The <ipv4> attribute contains the IP address of the VM."
        $retVal = 1
    }

    # Check the <sshkey> tag
    if (!$vm.sshKey -and !$vm.password)
    {
        LogMsg 0 "Error: The VM $($vm.vmName) is missing the <sshKey> or <password> tag."
        LogMsg 0 "Error: The vm must define either <sshKey> or <password>"
        $retVal = 1
    }

    # Check the <snapshotname> tag
    if (! $vm.snapshotname)
    {
        LogMsg 0 "Warn : The VM $($vm.vmName) is missing the <snapshotname> tag."
        LogMsg 0 "Warn : The snapshot name defaults to ICABase"
    }
    
    # Check the <suites> tag.
    if (! $vm.suite)
    {
        LogMsg 0 "Error: The VM $($vm.vmName) is missing the <suite> tag."
        LogMsg 0 "Error: The <test> attribute is a comma separated list of tests the VM will run."
        $retVal = 1
    }
    else
    {
        #
        # For each test suite is defined
        #
        $testSuiteName = $vm.suite
        $found = $false
        foreach($suite in $xmlData.config.testSuites.suite)
        {
            if ($suite.suiteName -eq $testSuiteName)
            {
                $found = $true
                break
            }
        }
        
        if (! $found)
        {
            LogMsg 0 "Error: The test suite '$testSuiteName' for VM $($vm.vmName) is not defined"
            $retVal = 1
        }
    }

    return $retVal
}


#######################################################################
#
# CheckTagName
#
# Description:
#     Confirm the tag tag is a known tag.  This check hopes to 
#     catch typo's in the .xml file.
#
#######################################################################
function CheckTagName([string]$name)
{
    $retVal = 0

    switch($name)
    {
    #core tags
    "config"           {}
    
    # Global tags
    "global"           {}
    "email"            {}
    "sender"           {}
    "subject"          {}
    "recipients"       {}
    "to"               {}
    "smtpServer"       {}
    "logfileRootDir"   {}
    "defaultSnapshot"  {}

    # Test Suite tags
    "testSuites"       {}
    "suite"            {}
    "suitename"        {}
    "suiteTests"       {}
    "suiteTest"        {}
    
    # Test tags
    "testCases"        {}
    "test"             {}
    "testName"         {}
    "testScript"       {}
    "timeout"          {}
    "files"            {}
    "testparams"       {}
    "param"            {}
    "setupScript"      {}
    "cleanupScript"    {}
    "noReboot"         {}
    "onError"          {}
    
    # VM tags
    "VMs"              {}
    "vm"               {}
    "hvServer"         {}
    "vmName"           {}
    "os"               {}
    "ipv4"             {}
    "sshKey"           {}
    "password"         {}
    "testSuite"        {}
    "currentTest"      {}
    "stateTimestamp"   {}
    "state"            {}
    "emailSummary"     {}
    "snapshotName"     {}

    default { LogMsg 0 "Warn : Unknown tag: <${name}>"
              $retVal = 1 }        
    }

    return $retVal
}


#######################################################################
#
# Find UndefinedTags
#
# Description:
#     For each tag in the .xml file, check to make sure it is a
#     tag known to be in an ICA .xml file.
#
#######################################################################
function FindUndefinedTags($node)
{
    $retVal = 0

    if ($node.NodeType -eq [System.Xml.XmlNodeType]::Element)
    {
        $sts = CheckTagName $node.Name
        if ($sts -ne 0)
        {
            $retVal = 1
        }
    }

    if ($node.HasChildNodes)
    {
        foreach ($child in $node.ChildNodes)
        {
            $sts = FindUndefinedTags $child
            if ($sts -ne 0)
            {
                $retVal = 1
            }
        }
    }

    return $retVal
}


#######################################################################
#
#  CheckHypervServers
#
#  Description:
#    Check the settings for Hyper-V server.  The following
#    checks are performed for each <vm> entry in the .xml file
#      - Check the hyperv server ip address is valid - <hvServer> tag
#      - The server has the vmms service installed and it is running.
#
#    Note: These checks are performed by actually connecting to 
#          the Hyper-V servers.
#
#######################################################################
function CheckHypervServers([XML] $xmlConfig)
{
    $retVal = 0

    foreach($vm in $xmlConfig.config.VMs.vm)
    {
        #
        # Hyper-V server checks
        #
        $os = gwmi -computername $vm.hvServer Win32_OperatingSystem
        if ($?)
        {
            #
            # Make sure is it a server
            if ($os.ProductType -ne 2 -and $os.ProductType -ne 3)
            {
                LogMsg 0 "Error: The Hyper-V server for VM $($vm.vmName) is not a server SKU"
                $retVal = 1
            }
        }
        else
        {
            LogMsg 0 "Warn : The Hyper-V server for VM $($vm.vmName) is incorrect, or the Hyper-v server is not running."
            $retVal = 1
        }

        #
        # Check if the Hyper-v server has the Hyper-V service, and the service is running.
        $vmms = gwmi -computername $vm.hvServer -query "select * from win32_service where name='vmms'"
        if ($?)
        {
            if (!$vmms.state.equals("Running"))
            {
                LogMsg 0 "Warn : The Hyper-V service is not running on the Hyper-V server for VM $($vm.vmName)"
                $retVal = 1
            }
        }
        else
        {
            LogMsg 0 "Error: The Hyper-V service in not installed on the Hyper-V server for VM $($vm.vmName)"
            $retVal = 1
        }
    }

    return $retVal
}

#######################################################################
#
# WaitForVMToStart
#
# Description:
#     Wait until a ping is successfully set to the target VM, or
#     the timeout period expires.
#
#######################################################################
function WaitForVMToStart($vm)
{
    $retVal = $false
    $machineUp = 0
    $timeout = 120
    $elapsedTime = 0
    
    while ($elapsedTime -le $timeout)
    {
        if (test-connection -count 1 -quiet $vm.ipv4)
        {
            $retVal = $true
            break
        }
        start-sleep -seconds 1
        $elapsedTime += 1
    }
    return $retVal
}


#######################################################################
#
#  CheckVirtualMachines
#
#  Description:
#    Check the connectivity settings for each VM.  The following
#    checks are performed for each <vm> entry in the .xml file
#      - Check for a valid IPv4 address - <ipv4> tag
#            This check connects to the VM 
#
#      - Check that the SSH key works   - <sshKey> tag
#            This check connects to the VM using SSH and using
#            the SSH key for authentication.
#
#      - Check that the atd service is installed and atd is running.
#
#    Note: These checks are performed by actually connecting to 
#          the Virtual machines.  This requires the VM be started.
#
#
#######################################################################
function CheckVirtualMachines([XML] $xmlConfig)
{
    $retVal = 0
    $timeout = 120      # 2 minute timeout
    $elapsedTime = 0
                
    foreach($vm in $xmlConfig.config.VMs.vm)
    {
        $vmname = $vm.vmName
        $hvserver = $vm.hvServer
        
        # Is the VM defined on the Server
        if ($null -eq (Get-VM $vm.vmName -server $vm.hvServer))
        {
            LogMsg 0 "The VM $($vm.vmName) does not exist on Hyper-V server $($vm.hvServer)"
            $retVal = 1
        }
        else
        {
            LogMsg 1 "Info : CheckVirtualMachines - $vmname exists on Hyper-V server $hvserver"
            
            #  Start each VM if it is not already started.
            $vmState = $vm.EnabledState
            if ($vmState -ne 2)
            {
                LogMsg 1 "Info : CheckVirtualMachines - Starting VM $vmname"
                Start-VM $vm -server $vm.hvServer
                while ($elapsedTime -le $timeout)
                {
                    $v = Get-VM $vm.vmName -server $vm.hvServer
                    $vmState = $v.EnabledState
                    if ($vmState -eq 2)
                    {
                        break
                    }
                    start-sleep -seconds 1
                    $elapsedTime += 1
                }
                
                if ($elapsedTime -ge $timeout)
                {
                    LogMsg 0 "Warn : Unable to start the VM $($vm.vmName)"
                    $retVal = 1
                }
            }
        }
    }
    
    #
    # The VMs are starting - ie. they entered the Hyper-V state of running.  We need to give them
    # some time to finish booting.  Then perform the checks of IP address, SSH key, and that atd
    # is running.
    #
    foreach ($vm in $xmlConfig.config.VMs.vm)
    {
        $vmname = $vm.vmName
        
        LogMsg 1 "Info : CheckVirtualMachines - Waiting for VM $vmName to finish booting"
        if (WaitForVMToStart($vm))
        {
            LogMsg 1 "Info : CheckVirtualMachines - $vmname is up and running."
            $ipAddr = $vm.ipv4

            $sshkey = $vm.sshkey
            LogMsg 1 "Info : CheckVirtualMachines - Establishing SSH connection to VM $vmName"
            LogMsg 5 "          plink -i .\ssh\$sshkey test@${ipAddr} ls"

            echo y | bin\plink -i .\ssh\${sshKey} root@${ipAddr} exit
            $data = bin\plink -i .\ssh\${sshkey} root@${ipAddr} ls
            if (! $?)
            {
                $addrFound = (arp -a | select-string -quiet -simpleMatch -pattern $ipAddr)
                if ($addrFound)
                {
                    # TCP connection looks good, so SSH key is questionable
                    LogMsg 0 "Warn : SSH key for $($vm.vmName) may be bad or not setup correctly."                   
                }
                else
                {
                    # Could not creat TCP/IP connection
                    LogMsg 0 "Warn : IP address for $($vm.vmName) may be bad."
                }
                $retVal = 1
            }
            else
            {
                # We successfully created an ssh connection.  Next, check that atd is running.
                $data = bin\plink -i .\ssh\${sshkey} root@$ipAddr ps -C atd
                if (!$?)
                {
                    # The ps command failed to find atd
                    LogMsg 0 "Warn : The atd process is not running on vm $($vm.vmName)"
                    $retVal = 1
                }
            }
        }
        else
        {
            LogMsg 0 "Error: No network connectivity with vm $($vm.vmName)"
            $retVal = 1
        }
    }
    
    # Perform the tests for each VM
    LogMsg 5 "Info : CheckVirtualMachines() returning $retVal"
    return $retVal
}


#######################################################################
#
# ValidateUserXmlFile
#
# Description:
#     Entry function for xml validation
#
#######################################################################
function ValidateUserXmlFile ([string] $xmlFilename, [switch] $checkhv, [switch] $checkvm)
{
    if (! $xmlFilename)
    {
        LogMsg 0 "Error: Missing the xmlConfigFile command-line argument"
        return 10
    }

    if (! (test-path $xmlFilename))
    {
        LogMsg 0 "Error: The file '$xmlFilename' does not exist"
        return 20
    }

    $xmlConfig = [xml] (Get-Content -Path $xmlFilename)
    if ($null -eq $xmlConfig)
    {
        LogMsg 0 "Error: Unable to parse the file $xmlFilename"
        LogMsg 0 "Error: This is usually caused by an XML tag mismatch, or incomplete XML tags"
        return 30
    }

    #
    # Check each section of the .xml file
    #
    DoGlobalChecks $xmlConfig
    DoSuiteChecks $xmlConfig
    DoTestsChecks $xmlConfig
    DoVMsChecks $xmlConfig
    FindUndefinedTags $xmlConfig

    #
    # Check that the Hyper-V servers referenced in the .xml file
    # are accessable, are Windows servers and have Hyper-v installed.
    #
    if ($checkhv)
    {
        CheckHypervServers $xmlConfig
    }

    #
    # Check VM's IP address, it's ssh key and confirm that atd is
    # installed and running.
    #
    if ($checkvm)
    {
        CheckVirtualMachines $xmlConfig
    }
}
