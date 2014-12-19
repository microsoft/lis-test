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
    Functions that make up the Lisa state engine; without the Hyper-V provisioning steps

.Description
    This PowerShell script implements the state engine which
    moves test execution against through the various states required to perform
    a test on any target Linux machine.  Not all states are visited by each
    machine.  The test case definition will result in some states
    being skipped.

    A fairly complete list of states a machine might progress through
    would include the following.  The below descriptions are not
    complete.  The intent is to give the reader an understanding
    of what is done in each state and the possible state transitions.

      LoadNextTest
        - Update the current test.
        - If no more tests set currentState to Finished
        - If test case has a setup script
            set currentState to RunSetupScript
        - else
            set currentState to SystemUp

      RunSetupScript
        - Run the setup script (to reconfigure the target machine)
        - Set currentState to StartSystem

      SystemUp
        - Send a simple command to the machine via SSH and accept any prompts for server key
        - Set currentState to PushTestFiles

      PushTestFiles
        - Create a constants.sh file and populate with all test parameters
        - Push the constants.sh file to machine using SSH
        - Tell the machine to run dos2unix on the constants.sh file
        - Push the test script to the machine
        - Tell the machine to run dos2unix on the test script file
        - Tell the machine to chmod 755 testScript
        - If test case has a pretest script
            set currentState to RunPreTestScript
          else
            set currentState to StartTtest

      RunPreTestScript
        - Verify test case lists a pretest script
        - Run the PowerShell pretest script in a separate PowerShell context
        - set currentState to StartTest

      StartTest
        - Create a Linux command to run the test case script
        - Write the command to a file named runtest.sh
        - copy runtest.sh file to machine
        - Tell machine to chmod 755 runtest.sh
        - Tell machine to run dos2unix on runtest.sh
        - Tell machine to start atd daemon
        - send command "at -f runtest.sh now" to machine
            This runs test script with both STDOUT and STDERR logged
            and allows the SSH connection to be closed.  This is needed
            so this script can process other machines in parallel
        - set currentState to TestStarting

      TestStarting
        - test if the file ~/state.txt was created on the machine
        - if state.txt exists
            set currentState to TestRunning

      TestRunning
        - Copy ~/state.txt from machine using SSH
        - if contents of state.txt is not "TestRunning"
            set currentState to CollectLogFiles

      CollectLogFiles
        - Use state.txt to mark status of test case to completed, aborted, failed
        - Copy log file from machine and save in Lisa test directory
          Note: The saved logfile will be named:  <hostName>_<testCaseName>.log
                This is required since the test run may have multiple machines and
                each machine may run the same test cases.
        - Delete state.txt on the machine
        - If test case has a posttest script
            Set currentState to RunPostTestScript
          else
            Set currentState to DetermineReboot

      RunPostTestScript
        - Verify test case lists a posttest script
        - Run the PowerShell posttest script in a separate PowerShell context
        - Set currentState to DetermineReboot

      DetermineReboot
        - Determine how to handle transition to next test, based on specified reboot/continueonerror settings in XML file
        - if reboot required
            Set currentState to RunCleanupScript if a cleanup script exists; otherwise set it to LoadNextTest 
          else
            Update currentTest
            Set currentState to SystemUp (which essentially skips RunCleanupScript for this test and RunSetupScript for next test)
            
      RunCleanUpScript
        - Run the cleanup secript (to undo configuration changes)
        - Set currentState to LoadNextTest

.Link
    None.
#>


#
# As a safety measure, try to unload hyperv module just in case someone
# loaded it in their PowerShell context before running this script.
#
$MNs = Get-Module

foreach($MN in $MNs)
{
    if($($MN.Name) -eq "Hyperv")
    {
        Remove-Module -Name $($MN.Name)
    }
}

#
# Source the other files we need
#
. .\utilFunctions.ps1 | out-null
. .\OSAbstractions.ps1

#
# Constants
#
# States a machine can be in
#
New-Variable LoadNextTest        -value "LoadNextTest"          -option ReadOnly
New-variable RunSetupScript      -value "RunSetupScript"      -option ReadOnly
New-Variable SystemUp            -value "SystemUp"            -option ReadOnly
New-Variable WaitForDependencyMachine -value "WaitForDependencyMachine" -option ReadOnly
New-Variable PushTestFiles       -value "PushTestFiles"       -option ReadOnly
New-Variable RunPreTestScript    -value "RunPreTestScript"    -option ReadOnly
New-Variable StartTest           -value "StartTest"           -option ReadOnly
New-Variable TestStarting        -value "TestStarting"        -option ReadOnly
New-Variable TestRunning         -value "TestRunning"         -option ReadOnly
New-Variable CollectLogFiles     -value "CollectLogFiles"     -option ReadOnly
New-Variable RunPostTestScript   -value "RunPostTestScript"   -option ReadOnly
New-Variable DetermineReboot     -value "DetermineReboot"     -option ReadOnly
New-variable RunCleanUpScript    -value "RunCleanUpScript"    -option ReadOnly

New-Variable StartPS1Test        -value "StartPS1Test"        -option ReadOnly
New-Variable PS1TestRunning      -value "PS1TestRunning"      -option ReadOnly
New-Variable PS1TestCompleted    -value "PS1TestCompleted"    -option ReadOnly

New-Variable Finished            -value "Finished"            -option ReadOnly
New-Variable Disabled            -value "Disabled"            -option ReadOnly

#
# test completion codes
#
New-Variable TestCompleted       -value "TestCompleted"       -option ReadOnly
New-Variable TestAborted         -value "TestAborted"         -option ReadOnly
New-Variable TestFailed          -value "TestFailed"          -option ReadOnly

#
# Supported OSs
#
New-Variable LinuxOS             -value "Linux"               -option ReadOnly
New-Variable FreeBSDOS           -value "FreeBSD"             -option ReadOnly


########################################################################
#
# RunICTestsWithoutHv()
#
########################################################################
function RunICTestsWithoutHv([XML] $xmlConfig)
{
    <#
    .Synopsis
        Start tests running on the test machines.
    .Description
        Add any additional any missing "required" XML elements to each
        machine definition.  Initialize the e-mail message that may be sent
        on test completion.
    .Parameter xmlConfig
        XML document driving the test.
    .Example
        RunICTests $xmlData
    #>

    if (-not $xmlConfig -or $xmlConfig -isnot [XML])
    {
        LogMsg 0 "Error: RunICTests received an bad xmlConfig parameter - terminating LISA"
        return
    }

    #LogMsg 9 "Info : RunICTests($($machine.hostName))"

    #
    # Verify the Putty utilities exist.  Without them, we cannot talk to the Linux machine.
    #
    if (-not (Test-Path -Path ".\bin\pscp.exe"))
    {
        LogMsg 0 "Error: The putty utility .\bin\pscp.exe does not exist"
        return
    }

    if (-not (Test-Path -Path ".\bin\plink.exe"))
    {
        LogMsg 0 "Error: The putty utility .\bin\plink.exe does not exist"
        return
    }

    #
    # Reset each machine to a known state
    #
    foreach ($machine in $xmlConfig.config.VMs.vm)
    {
        LogMsg 5 "Info : RunICTests() processing machine $($machine.hostname)"
        $isSUT = $false

        if ($machine.role -eq $null)
        {
            $newElement = $xmlConfig.CreateElement("role")
            $newElement.set_InnerText("SUT")
            $results = $machine.AppendChild($newElement)
        }
        elseif ($machine.role -ne "sut" -and $machine.role -ne "nonsut")
        {
            LogMsg 0 "Error: Unknown machine role specified in the XML file: $($machine.role). It should be either 'sut' or 'nonsut'"
            return
        }
        
        #
        # Add the state related xml elements to each xml node
        #
        $xmlElementsToAdd = @("currentTest", "stateTimeStamp", "state", "emailSummary", "jobID", "testCaseResults", "iteration")
        foreach($element in $xmlElementsToAdd)
        {
            if (-not $machine.${element})
            {
                $newElement = $xmlConfig.CreateElement($element)
                $newElement.set_InnerText("none")
                $results = $machine.AppendChild($newElement)
            }
        }

        # Add empty vmName and hyperv server properties to this machine; setup/cleanup scripts will fail to be invoked if these properties are absent
        $newElement = $xmlConfig.CreateElement("vmName")
        $newElement.set_InnerText("")
        $results = $machine.AppendChild($newElement)

        $newElement = $xmlConfig.CreateElement("hvServer")
        $newElement.set_InnerText("")
        $results = $machine.AppendChild($newElement)
        
        #
        # Correct the default iteration value
        #
        $machine.iteration = "-1"

        #
        # Add machine specific information to the email summary text
        #
        $machine.emailSummary = "Machine: $($machine.hostname)<br />"
        $machine.emailSummary += "IP Address (v4): $($machine.ipv4)<br />"
        $machine.emailSummary += "Role: $($machine.role)<br />"
        $machine.emailSummary += "<br /><br />"

        $machine.state = $LoadNextTest
    }

    #
    # run the state engine
    #
    DoStateMachine $xmlConfig
}

########################################################################
#
# DoStateMachine()
#
########################################################################
function DoStateMachine([XML] $xmlConfig)
{
    <#
    .Synopsis
        Main function of the state machine.
    .Description
        Move each machine through the various states required
        to run a test on it.
    .Parameter xmlConfig
        XML document for the test.
    .Example
        DoStateMachine $xmlData
    #>

    LogMsg 9 "Info : Entering DoStateMachine()"

    $done = $false
    while(! $done)
    {
        $done = $true  # Assume we are done
        foreach( $machine in $xmlConfig.config.VMs.vm )
        {
            switch($machine.state)
            {
            $LoadNextTest
                {
                    DoLoadNextTest $machine $xmlConfig
                    $done = $false
                }

            $RunSetupScript
                {
                    DoRunSetupScript $machine $xmlConfig
                    $done = $false
                }

            $SystemUp
                {
                    DoSystemUp $machine $xmlConfig
                    $done = $false
                }

            $PushTestFiles
                {
                    DoPushTestFiles $machine $xmlConfig
                    $done = $false
                }

            $RunPreTestScript
                {
                    DoRunPreTestScript $machine $xmlConfig
                    $done = $false
                }

            $WaitForDependencyMachine
                {
                    DoWaitForDependencyMachine $machine $xmlConfig
                    $done = $false
                }

            $StartTest
                {
                    DoStartTest $machine $xmlConfig
                    $done = $false
                }

            $TestStarting
                {
                    DoTestStarting $machine $xmlConfig
                    $done = $false
                }

            $TestRunning
                {
                    DoTestRunning $machine $xmlConfig
                    $done = $false
                }

            $CollectLogFiles
                {
                    DoCollectLogFiles $machine $xmlConfig
                    $done = $false
                }

            $RunPostTestScript
                {
                    DoRunPostTestScript $machine $xmlConfig
                    $done = $false
                }

            $DetermineReboot
                {
                    DoDetermineReboot $machine $xmlConfig
                    $done = $false
                }

            $RunCleanupScript
                {
                    DoRunCleanUpScript $machine $xmlConfig
                    $done = $false
                }

            $StartPS1Test
                {
                    DoStartPS1Test $machine $xmlConfig
                    $done = $false
                }

            $PS1TestRunning
                {
                    DoPS1TestRunning $machine $xmlConfig
                    $done = $false
                }

            $PS1TestCompleted
                {
                    DoPS1TestCompleted $machine $xmlConfig
                    $done = $false
                }

            $Finished
                {
                    # Nothing to do in the Finished state
                }

            $Disabled
                {
                    # no-op
                }

            default:
                {
                    LogMsg 0 "Error: State machine encountered an undefined state for VM $($machine.hostName), State = $($machine.state)"
                    $machine.currentTest = "done"
                    UpdateState $machine $Finished
                }
            }
        }
        Start-Sleep -m 100
    }

    LogMsg 5 "Info : DoStateMachine() exiting"
}


########################################################################
#
# DoLoadNextTest()
#
########################################################################
function DoLoadNextTest([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Ensure that test resources required by this machine are available and machine is running and ready to accept SSH connections
    .Description
        Update the machine's currentTest.  Transition to RunSetupScript if the currentTest
        defines a setup script.  Otherwise, transition to StartSystem
    .Parameter machine
        XML Element representing the machine under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoLoadNextTest $testVM $xmlData
    #>

    LogMsg 9 "Info : Entering DoLoadNextTest( $($machine.hostname) )"

    if ($machine.role -eq "sut")
    {
        #for SUT machines:

        #
        # Update the machine's current test
        #
        UpdateCurrentTest $machine $xmlData
    
        $iterationMsg = $null
        if ($machine.iteration -ne "-1")
        {
            $iterationMsg = " (iteration $($machine.iteration))"
        }
        LogMsg 0 "Info : $($machine.hostname) currentTest updated to $($machine.currentTest) ${iterationMsg}"

        if ($($machine.currentTest) -eq "done")
        {
            UpdateState $machine $Finished
        }
        else
        {
            $testData = GetTestData $machine.currentTest $xmlData
            if ($testData -is [System.Xml.XmlElement])
            {
                if (-not (VerifyTestResourcesExist $machine $testData))
                {
                    #
                    # One or more resources used by the machine or test case does not exist - fail the test
                    #
                    $testName = $testData.testName
                    $machine.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Failed")
                    $machine.emailSummary += "          Missing resources<br />"
                    return
                }

                if ($machine.preStartConfig -or $testData.setupScript)
                {
                    UpdateState $machine $RunSetupScript
                }
                else
                {
                    UpdateState $machine $SystemUp
                }
            }
            else
            {
                LogMsg 0 "Error: No test data for test $($machine.currentTest) in the .xml file`n       $($machine.hostName) has been disabled"
                $machine.emailSummary += "          No test data found for test $($machine.currentTest)<br />"
                $machine.currentTest = "done"
                UpdateState $machine $Disabled
            }
        }
    }
    else
    {
        #for NON-SUT machines, put the machine state to run preStartScript or StartSystem
        if ($machine.preStartConfig)
        {
            UpdateState $machine $RunSetupScript
        }
        else
        {
            UpdateState $machine $SystemUp
        }
    }
}


########################################################################
#
# DoRunSetupScript()
#
########################################################################
function DoRunSetupScript([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Run a setup script to reconfigure a machine.
    .Description
        If the currentTest has a setup script defined, run the
        setup script to reconfigure the machine.
    .Parameter machine
        XML Element representing the machine under test.
    .Parameter xmlData
        XML document for the test.
    .Example
        DoRunSetupScript $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunSetupScript() was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : DoRunSetupScript( $($machine.hostName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunSetupScript received a null or bad xmlData parameter - terminating VM"
        $machine.currentTest = "done"
        UpdateState $machine $Disabled
    }

    #run preStartScript if has
    if ($machine.preStartConfig)
    {
        LogMsg 3 "Info : $($machine.hostName) - starting preStart script $($machine.preStartConfig)"

        $sts = RunPSScript $machine $($machine.preStartConfig) $xmlData "preStartConfig"
        if (-not $sts)
        {
            LogMsg 0 "Error: Info: Machine $($machine.hostName) preStartConfig script for test $($machine.postStartConfig) failed"
        }
    }
    else
    {
        LogMsg 9 "Info: Machine: $($machine.hostName) does not have preStartConfig script defined"
    }

    if ($machine.role -eq "sut")
    {
        #for SUT machines:
        #
        # Run setup script if one is specified (this setup Script is defined in testcase level)
        #
        $testData = GetTestData $($machine.currentTest) $xmlData
        if ($testData -is [System.Xml.XmlElement])
        {
            $testName = $testData.testName
            $abortOnError = $True
            if ($testData.onError -eq "Continue")
            {
                $abortOnError = $False
            }

            if ($testData.setupScript)
            {
                if ($testData.setupScript.File)
                {
                    foreach ($script in $testData.setupScript.File)
                    {
                        LogMsg 3 "Info : $($machine.hostName) - running setup script '${script}'"
 
                        if (-not (RunPSScript $machine $script $xmlData "Setup" $logfile))
                        {
                            #
                            # If the setup script fails, fail the test. If <OnError>
                            # is continue, continue on to the next test in the suite.
                            # Otherwise, terminate testing.
                            #
                            LogMsg 0 "Error: VM $($machine.hostName) setup script ${script} for test ${testName} failed"
                            $machine.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Failed - setup script failed")
                            #$machine.emailSummary += ("    Test {0,-25} : {2}<br />" -f $($machine.currentTest), $iterationMsg, $completionCode)
                            if ($abortOnError)
                            {
                                $machine.currentTest = "done"
                                UpdateState $machine $finished
                                return
                            }
                            else
                            {
                                UpdateState $machine $LoadNextTest
                                return
                            }
                        }
                    }
                }
                else  # the older, single setup script syntax
                {
                    LogMsg 3 "Info : $($machine.hostName) - running single setup script '$($testData.setupScript)'"
            
                    if (-not (RunPSScript $machine $($testData.setupScript) $xmlData "Setup" $logfile))
                    {
                        #
                        # If the setup script fails, fail the test. If <OnError>
                        # is continue, continue on to the next test in the suite.
                        # Otherwise, terminate testing.
                        #
                        LogMsg 0 "Error: VM $($machine.hostName) setup script $($testData.setupScript) for test ${testName} failed"
                        #$machine.emailSummary += "    Test $($machine.currentTest) : Failed - setup script failed<br />"
                        $machine.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Failed - setup script failed")
                    
                        if ($abortOnError)
                        {
                            $machine.currentTest = "done"
                            UpdateState $machine $finished
                            return
                        }
                        else
                        {
                            UpdateState $machine $LoadNextTest
                            return
                        }
                    }
                }
            }
            else
            {
                LogMsg 9 "INFO : $($machine.hostName) does not have setup script defined for test $($machine.currentTest)"
            }
            UpdateState $machine $SystemUp
        }
        else
        {
            LogMsg 0 "Error: $($machine.hostName) could not find test data for $($machine.currentTest)`n       The VM $($machine.hostName) will be disabled"
            $machine.emailSummary += "Test $($machine.currentTest) : Aborted (no test data)<br />"
            $machine.currentTest = "done"
            UpdateState $machine $Disabled
        }
    }
    #for Non-SUT machines:
    # NonSUT will not run test cases directly so there will not have setup script defined
    else
    {
        UpdateState $machine $SystemUp
    }
}

########################################################################
#
# DoSystemUp()
#
########################################################################
function DoSystemUp([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Verify the system is up and accessible
    .Description
        Send a command to the machine and accept an SSH prompt for server
        key.
    .Parameter machine
        XML Element representing the machine under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoSystemUp $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemUp received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoSystemUp($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemUp received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoSystemUp received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $hostname = $machine.ipv4
    $sshKey = $machine.sshKey

    #
    # The first time we SSH into a VM, SSH will prompt to accept the server key.
    # Send a "no-op command to the VM and assume this is the first SSH connection,
    # so pipe a 'y' respone into plink
    #
	
    LogMsg 9 "INFO : Call: echo y | bin\plink -i ssh\$sshKey root@$hostname exit"
    echo y | bin\plink -i ssh\${sshKey} root@${hostname} exit

    #
    # Determine the VMs OS
    #
    $os = (GetOSType $machine).ToString()
    LogMsg 9 "INFO : The OS type is $os"

    #
    # Update the time on the Linux VM
    #
    #$dateTimeCmd = GetOSDateTimeCmd $machine
    #if ($dateTimeCmd)
    #{
        #$linuxDateTime = [Datetime]::Now.ToString("MMddHHmmyyyy")
        #LogMsg 3 "Info : $($machine.hostName) Updating time on the VM (${dateTimeCmd})."
        #if (-not (SendCommandToVM $machine "$dateTimeCmd") )
        #{
        #    LogMsg 0 "Error: $($machine.hostName) could not update time"
        #    $machine.emailSummary += "    Unable to update time on VM - test aborted<br />"
        #    $machine.testCaseResults = "False"
        #    UpdateState $machine $DetermineReboot
        #}
        #else
        #{
        #    UpdateState $machine $PushTestFiles
        #}
    #}
    #else
    #{
    #    UpdateState $machine $PushTestFiles
    #}

    If ($machine.role -eq "sut")
    {
         #for SUT VM, needs to wait for NonSUT VM startup
         UpdateState $machine $WaitForDependencyMachine
    }
    else
    {
         #for NonSUT VM, run postStartConfig now (map to SUT VM's RunPreTestScript State).
         UpdateState $machine $RunPreTestScript
    }
    
}


########################################################################
#
# DoPushTestFiles()
#
########################################################################
function DoPushTestFiles([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Push files to the VM
    .Description
        A test case may identify files to be pushed to a VM.
        If this current test lists any files, push these to 
        the test VM. Collect the test parameters into a file
        named constants.sh and push this file to the VM
        as well
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoPushTestFiels $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPushTestFiles received an bad null vm parameter"
        return
    }

    LogMsg 9 "Info : DoPushTestFiles($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPushTestFiles received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoPushTestFiles received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    #
    # Get test specific information
    #
    LogMsg 6 "Info : $($machine.hostName) Getting test data for current test $($machine.currentTest)"
    $testData = GetTestData $($machine.currentTest) $xmlData
    if ($null -eq $testData)
    {
        LogMsg 0 "Error: $($machine.hostName) no test named $($machine.currentTest) was found in xml file"
        $machine.emailSummary += "    No test named $($machine.currentTest) was found - test aborted<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    #
    # Delete any old constants files that may be laying around, then
    # create a new file for this test
    #
    $constFile = "constants.sh"
    if (test-path $constFile)
    {
        del $constFile -ErrorAction "SilentlyContinue"
    }
    
    if ($xmlData.config.global.testParams -or $testdata.testParams -or $machine.testParams)
    {
        #
        # First, add any global testParams
        #
        if ($xmlData.config.global.testParams)
        {
            LogMsg 9 "Info : $($machine.hostName) Adding glogal test params"
            foreach ($param in $xmlData.config.global.testParams.param)
            {
                ($param) | out-file -encoding ASCII -append -filePath $constFile
            }
        }
        
        #
        # Next, add any test specific testParams
        #
        if ($testdata.testparams)
        {
            LogMsg 9 "Info : $($machine.hostName) Adding testparmas for test $($testData.testName)"
            foreach ($param in $testdata.testparams.param)
            {
                ($param) | out-file -encoding ASCII -append -filePath $constFile
            }
        }
        
        #
        # Now, add VM specific testParams
        #
        if ($machine.testparams)
        {
            LogMsg 9 "Info : $($machine.hostName) Adding VM specific params"
            foreach ($param in $machine.testparams.param)
            {
                ($param) | out-file -encoding ASCII -append -filePath $constFile
            }
        }
    }

    #
    # Add the ipv4 param that we're using to talk to the VM. This way, tests that deal with multiple NICs can avoid manipulating the one used here
    #
    if ($machine.ipv4)
    {
        LogMsg 9 "Info : $($machine.hostName) Adding ipv4=$($machine.ipv4)"
        "ipv4=$($machine.ipv4)" | out-file -encoding ASCII -append -filePath $constFile
    }

    #
    # Add the iteration information if test case is being iterated
    #
    if ($machine.iteration -ne "-1")
    {
        "iteration=$($machine.iteration)" | out-file -encoding ASCII -append -filePath $constFile
        
        if ($testData.iterationParams)
        {
            $iterationParam = GetIterationParam $machine $xmlData
                    
            if ($iterationParam -and $iterationparam -ne "")
            {
                "iterationParam=${iterationParam}" | out-file -encoding ASCII -append -filePath $constFile
            }
        }
    }

    #
    # Push the constants file to the VM is it was created
    #
    if (test-path $constFile)
    {
        LogMsg 3 "Info : $($machine.hostName) Pushing constants file $constFile to VM"
        if (-not (SendFileToVM $machine $constFile $constFile) )
        {
            LogMsg 0 "Error: $($machine.hostName) cannot push $constFile to $($machine.hostName)"
            $machine.emailSummary += "    Cannot pushe $constFile to VM<br />"
            $machine.testCaseResults = "False"
            UpdateState $machine $DetermineReboot
            return
        }
        
        #
        # Convert the end of line characters in the constants file
        #
        $dos2unixCmd = GetOSDos2UnixCmd $machine $constFile
        #$dos2unixCmd = "dos2unix -q ${constFile}"

        if ($dos2unixCmd)
        {
            LogMsg 3 "Info : $($machine.hostName) converting EOL for file $constFile"
            if (-not (SendCommandToVM $machine "${dos2unixCmd}") )
            {
                LogMsg 0 "Error: $($machine.hostName) unable to convert EOL on file $constFile"
                $machine.emailSummary += "    Unable to convert EOL on file $constFile<br />"
                $machine.testCaseResults = "False"
                UpdateState $machine $DetermineReboot
                return
            }
        }
        else
        {
            LogMsg 0 "Error: $($machine.hostName) cannot create dos2unix command for ${constFile}"
            $machine.emailSummary += "    Unable to create dos2unix command for ${constFile}<br />"
            $machine.testCaseResults = "False"
            UpdateState $machine $DetermineReboot
            return
        }
        
        del $constFile -ErrorAction:SilentlyContinue
    }


    #
    # Push the files to the VM as specified in the <files> tag.
    #
    LogMsg 3 "Info : $($machine.hostName) Pushing files and directories to VM"
    if ($testData.files)
    {
        $files = ($testData.files).split(",")
        foreach ($f in $files)
        {
            $testFile = $f.trim()
            LogMsg 5 "Info : $($machine.hostName) sending '${testFile}' to VM"
            if (-not (SendFileToVM $machine $testFile) )
            {
                LogMsg 0 "Error: $($machine.hostName) error pushing file '$testFile' to VM"
                $machine.emailSummary += "    Unable to push test file '$testFile' to VM<br />"
                $machine.testCaseResults = "False"
                UpdateState $machine $DetermineReboot
                return
            }
        }
    }

    #
    # If the test script is a powershell script, transition to the appropriate state
    #
    $testScript = $($testData.testScript).Trim()
    if ($testScript -eq $null)
    {
        LogMsg 0 "Error: $($machine.hostName) test case $($machine.currentTest) does not have a testScript"
        $machine.emailSummary += "    Test case $($machine.currentTest) does not have a testScript.<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }
    else
    {
        if ($testScript.EndsWith(".ps1"))
        {
            UpdateState $machine $StartPS1Test
            return
        }
    }

    #
    # Make sure the test script has Unix EOL
    #
    LogMsg 3 "Info : $($machine.hostName) converting EOL for file $testScript"
    $dos2unixCmd = GetOSDos2UnixCmd $machine $testScript
    #$dos2unixCmd = "dos2unix -q $testScript"
    if ($dos2unixCmd)
    {
        if (-not (SendCommandToVM $machine "${dos2unixCmd}") )
        {
            LogMsg 0 "Error: $($machine.hostName) unable to set EOL on test script file $testScript"
            $machine.emailSummary += "    Unable to set EOL on file $testScript<br />"
            $machine.testCaseResults = "False"
            UpdateState $machine $DetermineReboot
            return
        }
    }
    else
    {
        LogMsg 0 "Error: $($machine.hostName) cannot create dos2unix command for ${testScript}"
        $machine.emailSummary += "    Unable to create dos2unix command for $testScript<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }
 
    #
    # Set the X bit to allow the script to run
    #
    LogMsg 3 "Info : $($machine.hostName) setting x bit on $testScript"
    if (-not (SendCommandToVM $machine "chmod 755 $testScript") )
    {
        LogMsg 0 "$($machine.hostName) unable to set x bit on test script $testScript"
        $machine.emailSummary += "    Unable to set x bit on test script $testScript<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    if ($($testData.preTest) )
    {
        UpdateState $machine $RunPreTestScript
    }
    else
    {
        UpdateState $machine $StartTest
    }
}


########################################################################
#
# DoRunPreTestScript()
#
########################################################################
function DoRunPreTestScript([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Run a pretest PowerShell script.
    .Description
        If the currentTest defines a PreTest script, run it
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoRunPreTestScript $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunPreTestScript() was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : DoRunPreTestScript( $($machine.hostName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunPreTestScript received a null or bad xmlData parameter - terminating VM"
    }
    else
    {
        If ($machine.role.ToLower().StartsWith("sut"))
        {
            #
            # For SUT VMs: Run pretest script if one is specified
            #
            $testData = GetTestData $($machine.currentTest) $xmlData
            if ($testData -is [System.Xml.XmlElement])
            {
                if ($testData.preTest)
                {
                    #
                    # If multiple pretest scripts specified
                    #
                    if ($testData.preTest.file)
                    {
                        foreach ($script in $testData.pretest.file)
                        {
                            LogMsg 3 "Info : $($machine.hostName) running PreTest script '${script}' for test $($testData.testName)"
                            $sts = RunPSScript $machine $script $xmlData "PreTest"
                            if (! $sts)
                            {
                                LogMsg 0 "Error: $($machine.hostName) PreTest script ${script} for test $($testData.testName) failed"
                            }
                        }
                    }
                    else # Original syntax of <pretest>setupscripts\myPretest.ps1</pretest>
                    {
                        LogMsg 3 "Info : $($machine.hostName) - starting preTest script $($testData.setupScript)"
                
                        $sts = RunPSScript $machine $($testData.preTest) $xmlData "PreTest"
                        if (-not $sts)
                        {
                            LogMsg 0 "Error: VM $($machine.hostName) preTest script for test $($testData.testName) failed"
                        }
                    }
                }
                else
                {
                    LogMsg 9 "Info: $($machine.hostName) entered RunPreTestScript with no preTest script defined for test $($machine.currentTest)"
                }
            }
            else
            {
                LogMsg 0 "Error: $($machine.hostName) could not find test data for $($machine.currentTest)"
            }
            UpdateState $machine $StartTest
        }
        else
        {
            #
            # For NonSUT VMs: Run postStartConfig script defined in the XML file, VM section
            #
            if ($machine.postStartConfig)
            {
                $sts = RunPSScript $machine $($machine.postStartConfig) $xmlData "postStartConfig"
                if (-not $sts)
                {
                    LogMsg 0 "Error: Info: NonSUT VM $($machine.hostName) postStartConfig script for test $($machine.postStartConfig) failed"
                }
            }
            else
            {
                LogMsg 9 "Info : NonSUT VM: $($machine.hostName) entered RunPreTestScript with no postStartConfig script defined"
            }

            UpdateState $machine $Finished
        }
    }
}


########################################################################
#
# DoStartTest()
#
########################################################################
function DoStartTest([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Start the test running on the VM
    .Description
        Create the runtest.sh, push it to the VM, set the x bit on the
        runtest.sh, start ATD on the VM, and submit runtest.sh vi at.
    .Parameter machine
        XML Element representing the machine under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoStartTest $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartTest received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoStartTest($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartTest received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoStartTest received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    #
    # Create a shell script to run the actual test script.
    # This is so the test script output can be directed into a specified log file.
    #
    del runtest.sh -ErrorAction "SilentlyContinue"
    
    #
    # Create the runtest.sh script, push it to the VM, set the x bit, then delete local copy
    #
    $testData = GetTestData $machine.currentTest $xmlData
    if (-not $testData)
    {
        LogMsg 0 "Error: $($machine.hostName) cannot fine test data for test '$($machine.currentTest)"
        $machine.emailSummary += "    Cannot fine test data for test '$($machine.currentTest)<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }
    
    #"./$($testData.testScript) &> $($machine.currentTest).log " | out-file -encoding ASCII -filepath runtest.sh
    $runCmd = GetOSRunTestCaseCmd $($machine.os) $($testData.testScript) "$($machine.currentTest).log"
    if (-not $runCmd)
    {
        LogMsg 0 "Error: $($machine.hostName) unable to create runtest.sh"
        $machine.emailSummary += "    Unable to create runtest.sh<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    $runCmd | out-file -encoding ASCII -filepath runtest.sh
    LogMsg 3 "Info : $($machine.hostName) pushing file runtest.sh"
    if (-not (SendFileToVM $machine "runtest.sh" "runtest.sh") )
    {
        LogMsg 0 "Error: $($machine.hostName) cannot copy runtest.sh to VM"
        $machine.emailSummary += "    Cannot copy runtest.sh to VM<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    del runtest.sh -ErrorAction:SilentlyContinue

    LogMsg 3 "Info : $($machine.hostName) setting the x bit on runtest.sh"
    if (-not (SendCommandToVM $machine "chmod 755 runtest.sh") )
    {
        LogMsg 0 "Error: $($machine.hostName) cannot set x bit on runtest.sh"
        $machine.emailSummary += "    Cannot set x bit on runtest.sh<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    $dos2unixCmd = GetOSDos2UnixCmd $machine "runtest.sh"
    #$dos2unixCmd = "dos2unix -q runtest.sh"
    if (-not $dos2unixCmd)
    {
        LogMsg 0 "Error: $($machine.hostName) cannot create dos2unix command for runtest.sh"
        $machine.emailSummary += "    Cannot create dos2unix command for runtest.sh<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    LogMsg 3 "Info : $($machine.hostName) correcting the EOL for runtest.sh"
    if (-not (SendCommandToVM $machine "${dos2unixCmd}") )
    {
        LogMsg 0 "Error: $($machine.hostName) Unable to correct the EOL on runtest.sh"
        $machine.emailSummary += "    Unable to correct the EOL on runtest.sh<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    #
    # Make sure atd daemon is running on the remote machine
    #
    LogMsg 3 "Info : $($machine.hostName) enabling atd daemon"
    #if (-not (SendCommandToVM $machine "/etc/init.d/atd start") )
    if (-not (StartOSAtDaemon $machine))
    {
        LogMsg 0 "Error: $($machine.hostName) Unable to start atd on VM"
        $machine.emailSummary += "    Unable to start atd on VM<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    #
    # Submit the runtest.sh script to the at queue
    #
    SendCommandToVM $machine "rm -f state.txt"
    LogMsg 3 "Info : $($machine.hostName) submitting job runtest.sh"
    if (-not (SendCommandToVM $machine "at -f runtest.sh now") )
    {
        LogMsg 0 "Error: $($machine.hostName) unable to submit runtest.sh to atd on VM"
        $machine.emailSummary += "    Unable to submit runtest.sh to atd on VM<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    UpdateState $machine $TestStarting
}


########################################################################
#
# DoTestStarting()
#
########################################################################
function DoTestStarting([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Check to see if the test actually started
    .Description
        When a test script starts, it will create a file on the
        VM named ~/state.txt.  Use SSH to verify if this file
        exists.
    .Parameter machine
        XML Element representing the machine under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoTestStarting $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoTestStarting received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoTestStarting($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoTestStarting received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoTestStarting received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $timeout = 600
    if ($machine.timeouts.testStartingTimeout)
    {
        $timeout = $machine.timeouts.testStartingTimeout
    }

    if ( (HasItBeenTooLong $machine.stateTimestamp $timeout) )
    {
        LogMsg 0 "Error: $($machine.hostName) time out starting test $($machine.currentTest)"
        $machine.emailSummary += "    time out starting test $($machine.currentTest)<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $DetermineReboot
        return
    }

    $stateFile = "state.txt"
    del $stateFile -ErrorAction "SilentlyContinue"
    if ( (GetFileFromVM $machine $stateFile ".") )
    {
        if ( (test-path $stateFile) )
        {
            UpdateState $machine $TestRunning
        }
    }
    del $stateFile -ErrorAction "SilentlyContinue"
}


########################################################################
#
# DoTestRunning()
#
########################################################################
function DoTestRunning([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Verify the test is still running on the VM
    .Description
        Use SSH to get a copy of ~/state.txt from the Linux
        VM and verify the contents.  The contents will be
        one of the following:
          TestRunning   - Test is still running
          TestCompleted - Test completed successfully
          TestAborted   - An error occured while setting up the test
          TestFailed    - An error occured during the test
        Leave this state once the value is not TestRunning
    .Parameter machine
        XML Element representing the machine under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoTestRunning $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoTestRunning received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoTestRunning($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoTestRunning received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoTestRunning received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $timeout = 10800
    $testData = GetTestData $machine.currentTest $xmlData
    if ($testData -and $testData.timeout)
    {
        $timeout = $testData.timeout
    }

    if ( (HasItBeenTooLong $machine.stateTimestamp $timeout) )
    {
        LogMsg 0 "Error: $($machine.hostName) time out running test $($machine.currentTest)"
        $machine.emailSummary += "    time out running test $($machine.currentTest)<br />"
        $machine.testCaseResults = "False"
        UpdateState $machine $CollectLogFiles
        return
    }

    $stateFile = "state.txt"

    del $stateFile -ErrorAction "SilentlyContinue"
    
    if ( (GetFileFromVM $machine $stateFile ".") )
    {
        if (test-path $stateFile)
        {
            $machine.testCaseResults = "Aborted"
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                if ($contents -eq $TestRunning)
                {
                    return
                }
                elseif ($contents -eq $TestCompleted)
                {
                    $machine.testCaseResults = "Success"
                    UpdateState $machine $CollectLogFiles
                }
                elseif ($contents -eq $TestAborted)
                {
                    AbortCurrentTest $machine "$($machine.hostName) Test $($machine.currentTest) aborted. See logfile for details"
                }
                elseif($contents -eq $TestFailed)
                {
                    AbortCurrentTest $machine "$($machine.hostName) Test $($machine.currentTest) failed. See logfile for details"
                    $machine.testCaseResults = "Failed"
                }
                else
                {
                    AbortCurrentTest $machine "$($machine.hostName) Test $($machine.currentTest) has an unknown status of '$($contents)'"
                }
                
                del $stateFile -ErrorAction "SilentlyContinue"
            }
            else
            {
                LogMsg 6 "Warn : $($machine.hostName) state file is empty"
            }
        }
        else
        {
            LogMsg 0 "Warn : $($machine.hostName) ssh reported success, but state file was not copied"
        }
    }
    else
    {
        LogMsg 0 "Warn : $($machine.hostName) unable to pull state.txt from VM."
    }
}


########################################################################
#
# DoCollectLogFiles()
#
########################################################################
function DoCollectLogFiles([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Collect files from the VM
    .Description
        Collect log file from the VM. Update th e-mail summary
        with the test results. Set the transition time.  Finally
        transition to FindNextAction to look at OnError, NoReboot,
        and our current state to determine the next action.
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoCollectLogFiles $testVM $xmlData
    #>
    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoCollectLogFiles received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoCollectLogFiles($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoCollectLogFiles received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoCollectLogFiles received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $currentTest = $machine.currentTest
    $iterationNum = $null
    if ($machine.iteration -ne "-1")
    {
        $iterationNum = $($machine.iteration)
    }

    #
    # Update the e-mail summary
    #
    $completionCode = "Aborted"
    if ( ($($machine.testCaseResults) -eq "Success") )
    {
        $completionCode = "Success"
    }
    elseif ( ($($machine.testCaseResults) -eq "Failed") )
    {
        $completionCode = "Failed"
    }
    
    $iterationMsg = $null
    if ($machine.iteration -ne "-1")
    {
        $iterationMsg = "($($machine.iteration))"
    }

    $machine.emailSummary += ("    Test {0,-25} : {2}<br />" -f $($machine.currentTest), $iterationMsg, $completionCode)
    
    #
    # Collect test results
    #
    $logFilename = "$($machine.hostName)_${currentTest}_${iterationNum}.log"
    LogMsg 4 "Info : $($machine.hostName) collecting logfiles"
    if (-not (GetFileFromVM $machine "${currentTest}.log" "${testDir}\${logFilename}") )
    {
        LogMsg 0 "Error: $($machine.hostName) DoCollectLogFiles() is unable to collect ${logFilename}"
    }

    #
    # Test case may optionally create a summary.log.
    #
    $summaryLog = "${testDir}\$($machine.hostName)__${currentTest}_summary.log"
    del $summaryLog -ErrorAction "SilentlyContinue"
    GetFileFromVM $machine "summary.log" $summaryLog
    if (test-path $summaryLog)
    {
        $content = Get-Content -path $summaryLog
        foreach ($line in $content)
        {
            $machine.emailSummary += "          $line<br />"
        }
        #Comment: The log parser may read VM information from this log file, such as Linux kernel version, etc. So don't delete this log:
        #del $summaryLog
    }

    #
    # If this test has additional files as specified in the <uploadFiles> tag,
    # copy these additional files from the VM.  Note - if there is an error
    # copying the file, just log a warning.
    #
    $testData = GetTestData $currentTest $xmlData
    if ($testData -and $testData.uploadFiles)
    {
        foreach ($file in $testData.uploadFiles.file)
        {
            LogMsg 9 "Info : Get '${file}' from VM $($machine.hostName)."
            $dstFile = "$($machine.hostName)_${currentTest}_${file}"
            if (-not (GetFileFromVM $machine $file "${testDir}\${dstFile}") )
            {
                LogMsg 0 "Warn : $($machine.hostName) cannot copy '${file}' from VM"
            }
        }
    }

    #
    # Also delete state.txt from the VM
    #
    SendCommandToVM $machine "rm -f state.txt"
    
    LogMsg 0 "Info : $($machine.hostName) Status for test $currentTest $iterationMsg = $completionCode"

    if ( $($testData.postTest) )
    {
        UpdateState $machine $RunPostTestScript
    }
    else
    {
        UpdateState $machine $DetermineReboot
    }
}


########################################################################
#
# DoRunPostTestScript()
#
########################################################################
function DoRunPostTestScript([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Run a post test PowerShell script.
    .Description
        If the currentTest defines a PostTest script, run it
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoRunPostTestScript $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        # This should never occur
        LogMsg 0 "Error: DoRunPostScript() was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : DoRunPostScript( $($machine.hostName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunPostTestScript received a null or bad xmlData parameter - terminating VM"
        $machine.currentTest = "done"
        UpdateState $machine $DetermineReboot
    }

    #
    # Run postTest script if one is specified
    #
    $testData = GetTestData $($machine.currentTest) $xmlData
    if ($testData -is [System.Xml.XmlElement])
    {
        if ($testData.postTest)
        {
            #
            # If multiple PostTest scripts specified
            #
            if ($testData.postTest.file)
            {
                foreach ($script in $testData.postTest.file)
                {
                    LogMsg 3 "Info : $($machine.hostName) running Post Test script '${script}' for test $($testData.testName)"
                    $sts = RunPSScript $machine $script $xmlData "PostTest"
                    if (! $sts)
                    {
                        LogMsg 0 "Error: $($machine.hostName) PostTest script ${script} for test $($testData.testName) failed"
                    }
                }
            }
            else # Original syntax of <postTest>setupscripts\myPretest.ps1</postTest>
            {
                LogMsg 3 "Info : $($machine.hostName) - starting postTest script $($testData.postTest)"
                $sts = RunPSScript $machine $($testData.postTest) $xmlData "PostTest"
                if (-not $sts)
                {
                    LogMsg 0 "Error: VM $($machine.hostName) postTest script for test $($testData.testName) failed"
                }
            }
        }
        else
        {
            LogMsg 0 "Error: $($machine.hostName) entered RunPostTestScript with no postTest script defined for test $($machine.currentTest)"
        }
    }
    else
    {
        LogMsg 0 "Error: $($machine.hostName) could not find test data for $($machine.currentTest)"
    }
    
    UpdateState $machine $DetermineReboot
}


########################################################################
#
# DoDetermineReboot()
#
########################################################################
function DoDetermineReboot([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Determine what the framework should do after a test has finished
    .Description
        Determine what to do before running the next test.  
        Look at OnError, NoReboot, and our current
        state to determine what our next state should be. 
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoDetermineReboot $testVm $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoDetermineReboot received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoDetermineReboot($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoDetermineReboot received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoDetermineReboot received a null xmlData parameter - disabling VM"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $testResults = $false
    
    if ( ($($machine.testCaseResults) -eq "Success") -or ($($machine.testCaseResults) -eq "True") )
    {
        $testResults = $true
    }
   
    $continueOnError = $true
    if ($testData.OnError -and $testData.OnError -eq "Abort")
    {
        $continueOnError = $false
    }

    $noReboot = $false
    if ($testData.NoReboot -and $testData.NoReboot -eq "true")
    {
        $noReboot = $true
    }
    
    #
    # Determine the next state we should transition to. Some of these require
    # setting current test to "done" so the LoadNextTest state will not run any
    # additional tests.
    #
    $nextState = "undefined"

    if ($testResults -or $continueOnError) #Test was successful or test can continue on error; so try to resume
    {
        # Reboot was specified means we should cleanup if necessary and go to next test
        if (!$noReboot)
        {
            $nextState = $LoadNextTest
        }
        # Reboot specified, means we should go straight to next test without cleaning up or running setup for next test
        else 
        {
            $nextState = $SystemUp
        }
    }
    else # current test failed and we are not allowed to continue; so just move on
    {
        # abort on error
        $nextState = $LoadNextTest
    }
    
    $nextTest = GetNextTest $machine $xmlData
    $testData = GetTestData $machine.currentTest $xmlData

    switch ($nextState)
    {
    $SystemUp
        {
            if ($($testData.cleanupScript))
            {
                LogMsg 0 "Warn : $($machine.hostName) The <NoReboot> flag prevented running cleanup script for test $($testData.testName)"
            }

            # We need to load the next test prior to going into SystemUp state; because SystemUp state skips test loading.
            # TODO: Fix this logic to avoid having to duplicate test loading in here
            UpdateCurrentTest $machine $xmlData

            $iterationMsg = $null
            if ($machine.iteration -ne "-1")
            {
                $iterationMsg = "(iteration $($machine.iteration))"
            }
            LogMsg 0 "Info : $($machine.hostName) currentTest updated to $($machine.currentTest) ${iterationMsg}"

            if ($machine.currentTest -eq "done")
            {
                UpdateState $machine $Finished
            }
            else
            {
                UpdateState $machine $SystemUp

                $nextTestData = GetTestData $nextTest $xmlData
                if ($($nextTestData.setupScript))
                {
                    LogMsg 0 "Warn : $($machine.hostName) The <NoReboot> flag prevented running setup script for test $nextTest"
                }
            }
        }
    $LoadNextTest
        {
            if ($testData -and $testData.cleanupScript)
            {
                UpdateState $machine $RunCleanUpScript
            }
            else
            {
                UpdateState $machine $LoadNextTest
            }
        }
    default
        {
            # We should never reach here.
            LogMsg 0 "Error: $($machine.hostName) DoDetermineReboot Inconsistent next state: $nextState"
            UpdateState $machine $Finished
            $machine.currentTest = "done"    # don't let the VM continue
        }
    }


}

########################################################################
#
# DoRunCleanUpScript()
#
########################################################################
function DoRunCleanUpScript($machine, $xmlData)
{
    <#
    .Synopsis
        Run a cleanup script
    .Description
        If the currentTest specified a cleanup script, run the
        script.  Setup and cleanup scripts are always PowerShell
        scripts.
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoRunCleanUpScript $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunCleanupScript received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoRunCleanupScript($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunCleanupScript received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoRunCleanupScript received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    #
    # Run cleanup script of one is specified.  Do not fail the test if the script
    # returns an error. Just log the error and condinue.
    #
    $currentTestData = GetTestData $($machine.currentTest) $xmlData
    if ($currentTestData -is [System.Xml.XmlElement] -and $currentTestData.cleanupScript)
    {
        #
        # If multiple cleanup scripts specified
        #
        if ($currentTestData.cleanupScript.file)
        {
            foreach ($script in $currentTestData.cleanupScript.file)
            {
                LogMsg 3 "Info : $($machine.hostName) running cleanup script '${script}' for test $($currentTestData.testName)"
                $sts = RunPSScript $machine $script $xmlData "Cleanup"
                if (! $sts)
                {
                    LogMsg 0 "Error: $($machine.hostName) cleanup script ${script} for test $($currentTestData.testName) failed"
                }
            }
        }
        else  # original syntax of <cleanupscript>setupscripts\myCleanup.ps1</cleanupscript>
        {
            LogMsg 3 "Info : $($machine.hostName) running cleanup script $($currentTestData.cleanupScript) for test $($currentTestData.testName)"
        
            $sts = RunPSScript $machine $($currentTestData.cleanupScript) $xmlData "Cleanup"
            if (! $sts)
            {
                LogMsg 0 "Error: $($machine.hostName) cleanup script $($currentTestData.cleanupScript) for test $($currentTestData.testName) failed"
            }
        }
    }
    else
    {
        LogMsg 0 "Error: $($machine.hostName) entered RunCleanupScript state when test $($machine.currentTest) does not have a cleanup script"
        $machine.emailSummary += "Entered RunCleanupScript but test does not have a cleanup script<br />"
    }

    UpdateState $machine $LoadNextTest
}


########################################################################
#
# DoFinished()
#
########################################################################
function DoFinished([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Finish up after the test run completed.
    .Description
        Finish up after the test run completed.  Currently, this state
        does not do anything.
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoFinished
    #>

    LogMsg 11 "Info : DoFinished( $($machine.hostName), xmlData )"
    LogMsg 11 "Info :   timestamp = $($machine.stateTimestamp))"
    LogMsg 11 "Info :   Test      = $($machine.currentTest))"
    
    # Currently, nothing to do...
}



########################################################################
#
# DoStartPS1Test()
#
########################################################################
function DoStartPS1Test([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Start a PowerShell test case script running
    .Description
        Some test cases run on the guest VM and others run
        on the Hyper-V host.  If the test case script is a
        PowerShell script, start it as a PowerShell job
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoStartPS1Test $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartPS1Test received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoStartPS1Test($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartPS1Test received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoStartPS1Test received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $machineName = $machine.hostName
    $hvServer = $machine.hvServer
    
    $currentTest = $machine.currentTest
    $testData = GetTestData $currentTest $xmlData
    $testScript = $testData.testScript
 
    $logFilename = "${TestDir}\${hostName}_${currentTest}_ps.log"

    $machine.testCaseResults = "False"
    
    if (! (test-path $testScript))
    {
        $msg = "Error: $machineName PowerShell test script does not exist: $testScript"
        LogMsg 0 $msg
        $msg | out-file $logFilename
        
        UpdateState $machine $PS1TestCompleted
    }
    else
    {
        #
        # Build a semicolon separated string of testParams
        #
        $params = CreateTestParamString $machine $xmlData
        $params += "scriptMode=TestCase;"
        $params += "ipv4=$($machine.ipv4);sshKey=$($machine.sshKey);"
        $msg = "Creating Log File for : $testScript"
        $msg | out-file $logFilename

        #
        # Start the PowerShell test case script
        #
        LogMsg 3 "Info : $machineName Run PowerShell test case script $testScript"
		LogMsg 3 "Info : hostName: $machineName"
		LogMsg 3 "Info : hvServer: $hvServer"
		LogMsg 3 "Info : params: $params"
        
        $job = Start-Job -filepath $testScript -argumentList $machineName, $hvServer, $params
        if ($job)
        {
            $machine.jobID = [string] $job.id
            UpdateState $machine $PS1TestRunning
        }
        else
        {
            LogMsg 0 "Error: $($machine.hostName) - Cannot start PowerShell job for test $currentTest"
            UpdateState $machine $PS1TestCompleted
        }
    }
}


########################################################################
#
# DoWaitForDependencyMachine()
#
########################################################################
function DoWaitForDependencyMachine([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        if XML defined nonSUT machines, then wait for it is ready (Setup configuration completed, and the VM transitioned to Finish)
    .Description
        Wait for all nonSUT machine finished the configuration
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoWaitForDependencyMachine $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoWaitForDependencyMachine received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoWaitForDependencyMachine($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoWaitForDependencyMachine received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoWaitForDependencyMachine received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    #if this is not a SUT VM, it should not wait for others.
    if ($machine.role -eq "nonsut")
    {
         LogMsg 3 "Warn : DoWaitForDependencyMachine() should not be called by a NonSUT VM"
         UpdateState $machine $Finished
    }
    else
    {
        #assume all NonSUT VM finished
        $allNonSUTsFinished = $true
        foreach( $v in $xmlData.config.VMs.vm )
        {
            if ($machine.role -eq "nonsut")
            {
                if ($($v.state) -ne $Finished)
                {
                    $allNonSUTsFinished = $false
                }
            }
        }

        if ($allNonSUTsFinished -eq $true)
        {
            UpdateState $machine $PushTestFiles
        }
    }
}

########################################################################
#
# DoPS1TestRunning()
#
########################################################################
function DoPS1TestRunning ([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Check if the PowerShell job running the test script has completed
    .Description
        Check if the PowerShell job running the test script has completed
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoPS1TestRunning $testVm $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPS1TestRunning received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoPS1TestRunning($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPS1TestRunning received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoPS1TestRunning received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $timeout = GetTestTimeout $machine $xmlData
    if ($machine.timeouts.ps1TestRunningTimeout)
    {
        $timeout = $machine.timeouts.ps1TestRunningTimeout
    }
   
    $tooLong = HasItBeenTooLong $machine.stateTimestamp $timeout
    if ($tooLong)
    {
        AbortCurrentTest $machine "test $($machine.currentTest) timed out."
        return
    }

    $jobID = $machine.jobID
    $jobStatus = Get-Job -id $jobID
    if ($jobStatus -eq $null)
    {
        # We lost our job.  Fail the test and stop tests
        $machine.currentTest = "done"
        AbortCurrentTest $machine "bad or incorrect jobId for test $($machine.currentTest)"
        return
    }
    
    if ($jobStatus.State -eq "Completed")
    {
        $machine.testCaseResults = "True"
        UpdateState $machine $PS1TestCompleted
    }
}


########################################################################
#
# DoPS1TestCompleted()
#
########################################################################
function DoPS1TestCompleted ([System.Xml.XmlElement] $machine, [XML] $xmlData)
{
    <#
    .Synopsis
        Collect test results
    .Description
        When the PowerShell job running completes, collect the output
        of the test job, write the output to a logfile, and report
        the pass/fail status of the test job.
    .Parameter machine
        XML Element representing the machine under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoPS1TestCompleted $testVM $xmlData
    #>

    if (-not $machine -or $machine -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPS1TestCompleted received an bad machine parameter"
        return
    }

    LogMsg 9 "Info : DoPS1TestCompleted($($machine.hostName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPS1TestCompleted received a null or bad xmlData parameter - disabling VM"
        $machine.emailSummary += "DoPS1TestCompleted received a null xmlData parameter - disabling VM<br />"
        $machine.currentTest = "done"
        UpdateState $machine $Finished
    }

    $machineName = $machine.hostName
    $currentTest = $machine.currentTest  
    $logFilename = "${TestDir}\${hostName}_${currentTest}_ps.log"
    $summaryLog  = "${hostName}_summary.log"

    #
    # Collect log data
    #
    $completionCode = "Failed"
    $jobID = $machine.jobID
    if ($jobID -ne "none")
    {
        $error.Clear()
        $jobResults = @(Receive-Job -id $jobID -ErrorAction SilentlyContinue)
        if ($jobResults)
        {
            if ($error.Count -gt 0)
            {
                "Error: ${currentTest} script encountered an error"
                $error[0].Exception.Message >> $logfilename
            }

            foreach ($line in $jobResults)
            {
                $line >> $logFilename
            }
            
            #
            # The last object in the $jobResults array will be the boolean
            # value the script returns on exit.  See if it is true.
            #
            if ($jobResults[-1] -eq $True)
            {
                $completionCode = "Success"
            }
        }

        Remove-Job -Id $jobID
    }
    
    LogMsg 0 "Info : ${hostName} Status for test $($machine.currentTest) = ${completionCode}"

    #
    # Update e-mail summary
    #
    #$machine.emailSummary += "    Test $($machine.currentTest)   : $completionCode.<br />"
    $machine.emailSummary += ("    Test {0,-25} : {1}<br />" -f $($machine.currentTest), $completionCode)
    if (test-path $summaryLog)
    {
        $content = Get-Content -path $summaryLog
        foreach ($line in $content)
        {
            $machine.emailSummary += "          ${line}<br />"
        }
        del $summaryLog
    }

    UpdateState $machine $DetermineReboot
}

