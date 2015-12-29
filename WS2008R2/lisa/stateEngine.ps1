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
#
# StateEngine.ps1
#
# description:
#     This is a Powershell script to automate the creation of Hyper-V
#     virtual machines (VMs).  This script supports installing the 
#     guest OS from a .iso file, or using an existing virtual hard
#     disk with an OS already installed.
#
#
########################################################################

#
# Load the HyperVLib version 2
# Note: For V2, the module can only be imported once into powershell.
#       If you import it a second time, the Hyper-V library function
#       calls fail.
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\Hyperv.psd1
}

. .\utilFunctions.ps1 | out-null
. .\OSAbstractions.ps1

#
# Constants
#
New-Variable SystemDown         -value "SystemDown"         -option ReadOnly
New-variable RunSetupScript     -value "RunSetupScript"     -option ReadOnly
New-Variable StartSystem        -value "StartSystem"        -option ReadOnly
New-Variable SystemStarting     -value "SystemStarting"     -option ReadOnly
New-Variable SlowSystemStarting -value "SlowSystemStarting" -option ReadOnly
New-Variable DiagnoseHungSystem -value "DiagnoseHungSystem" -option ReadOnly
New-Variable SystemUp           -value "SystemUp"           -option ReadOnly
New-Variable PushTestFiles      -value "PushTestFiles"      -option ReadOnly
New-Variable RunPreTestScript   -value "RunPreTestScript"   -option ReadOnly
New-Variable StartTest          -value "StartTest"          -option ReadOnly
New-Variable TestStarting       -value "TestStarting"       -option ReadOnly
New-Variable TestRunning        -value "TestRunning"        -option ReadOnly
New-Variable CollectLogFiles    -value "CollectLogFiles"    -option ReadOnly
New-Variable RunPostTestScript  -value "RunPostTestScript"  -option ReadOnly
New-Variable DetermineReboot    -value "DetermineReboot"    -option ReadOnly
New-Variable ShutdownSystem     -value "ShutdownSystem"     -option ReadOnly
New-Variable ShuttingDown       -value "ShuttingDown"       -option ReadOnly
New-Variable ForceShutDown      -value "ForceShutDown"      -option ReadOnly
New-variable RunCleanUpScript   -value "RunCleanUpScript"   -option ReadOnly

New-Variable StartPS1Test       -value "StartPS1Test"       -option ReadOnly
New-Variable PS1TestRunning     -value "PS1TestRunning"     -option ReadOnly
New-Variable PS1TestCompleted   -value "PS1TestCompleted"   -option ReadOnly

New-Variable Finished           -value "Finished"           -option ReadOnly
New-Variable Disabled           -value "Disabled"           -option ReadOnly

New-Variable TestCompleted      -value "TestCompleted"      -option ReadOnly
New-Variable TestAborted        -value "TestAborted"        -option ReadOnly
New-Variable TestFailed         -value "TestFailed"         -option ReadOnly

New-Variable LinuxOS            -value "Linux"              -option ReadOnly
New-Variable FreeBSDOS          -value "FreeBSD"            -option ReadOnly


########################################################################
#
# RunICTests()
#
# Description:
#    Reset all VMs to a known state of stopped.
#    Add any additional any missing "required" XML elements to each
#    vm definition.
#    Initialize the e-mail message that may be sent on test completion.
#
#    Pre-Conditions:
#        An xml file with valid syntax.
#
#    Post-Condition:
#        All VMs defined in the .xml file are either in a stopped state
#        or have been marked as Disabled (no tests will be run on the
#        VM).
#
# Parameters:
#     $xmlConfig : The parsed contents of the .xml file.
#
# Return:
#
########################################################################
function RunICTests([XML] $xmlConfig)
{
    if (-not $xmlConfig -or $xmlConfig -isnot [XML])
    {
        LogMsg 0 "Error: RunICTests received an invalid xmlConfig parameter - terminating LISA"
        return
    }

    LogMsg 9 "Info : RunICTests($($vm.vmName))"

    #
    # Reset each VM to a known state
    #
    foreach ($vm in $xmlConfig.config.VMs.vm)
    {
        LogMsg 5 "Info : RunICTests() processing VM $($vm.vmName)"
        
        #
        # Add the state related xml elements to each VM xml node
        #
        $xmlElementsToAdd = @("currentTest", "stateTimeStamp", "state", "emailSummary", "jobID", "testCaseResults", "iteration")
        foreach($element in $xmlElementsToAdd)
        {
            if (-not $vm.${element})
            {
                $newElement = $xmlConfig.CreateElement($element)
                $newElement.set_InnerText("none")
                $results = $vm.AppendChild($newElement)
            }
        }
        
        #
        # Correct the default iteration value
        #
        $vm.iteration = "-1"

        #
        # Add VM specific information to the email summary text
        #
        $vm.emailSummary = "VM: $($vm.vmName)<br />"
        $OSInfo = get-wmiobject Win32_OperatingSystem -computerName $vm.hvServer
        $vm.emailSummary += "    Server :  $($vm.hvServer)<br />"
        $vm.emailSummary += "    OS :  $($OSInfo.Caption)"
        if ($OSInfo.ServicePackMajorVersion -gt 0)
        {
            $vm.emailSummary += " SP $($OSInfo.ServicePackMajorVersion)"
        }
        $vm.emailSummary += " build $($OSInfo.BuildNumber)"
        $vm.emailSummary += "<br /><br />"
        
        #
        # Make sure the VM actually exists on the specific HyperV server
        #
        if ($null -eq (Get-VM $vm.vmName -server $vm.hvServer))
        {
            LogMsg 0 "Warn : The VM $($vm.vmName) does not exist on server $($vm.hvServer)"
            LogMsg 0 "Warn : Tests will not be run on $($vm.vmName)"
            UpdateState $vm $Disabled

            $vm.emailSummary += "    The virtual machine $($vm.vmName) does not exist.<br />"
            $vm.emailSummary += "    No tests were run on $($vm.vmName)<br />"
            continue
        }
        else
        {
            LogMsg 10 "Info : Resetting vm $($vm.vmName)"
            ResetVM $vm
        }
    }

    #
    # All VMs should be either in a ShutDown state, or disabled.  If that is not the case
    # we have a problem...
    #
    foreach ($vm in $xmlConfig.config.VMs.vm)
    {
        if ($vm.state -ne $Disabled -and $vm.state -ne $SystemDown)
        {
            LogMsg 0 "Error: RunICTests - $($vm.vmName) is not in a shutdown state"
            LogMsg 0 "Error:   The VM cannot be put into a stopped state"
            LogMsg 0 "Error:   Tests will not be run on $($vm.vmName)"
            $vm.emailSummay += "    The VM could not be stopped.  It has been disabled.<br />"
            $vm.emailSummary += "   No tests were run on this VM`<br />"
            UpdateState $vm $Disabled
        }
    }

    #
    # run the state engine
    #
    DoStateMachine $xmlConfig
}


########################################################################
#
# ResetVM()
#
# Description:
#    Stops the VM, and resets it to a snapshot
#
#    Pre-Conditions
#        A valid XmlElement that represents an actual virtual machine.
#        The current state of the VM is unknown.
#
#    Post Conditions
#        The actual VM is in a stopped state, or has been marked as
#        disabled in the XmlElement.
#
# Parameters:
#    $vm  : The XML object representing the VM to reset.
#
# Return:
#    None
#
########################################################################
function ResetVM([System.Xml.XmlElement] $vm)
{   
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: ResetVM was passed an invalid VM object"
        return
    }

    LogMsg 9 "Info : ResetVM( $($vm.vmName) )"

    #
    # Stop the VM.  If the VM is in a state other than running,
    # try to stop it.
    #
    $v = Get-VM $vm.vmName -server $vm.hvServer
    if ($v -eq $null)
    {
        LogMsg 0 "Error: ResetVM cannot find the VM $($vm.vmName) on HyperV server $($vm.hvServer)"
        $vm.emailSummary += "VM $($vm.vmName) cannot be found - no tests run on VM<br />"
        UpdateState $vm $Disabled
        return
    }

    #
    # If the VM is not stopped, try to stop it
    #
    if ($v.EnabledState -ne [VMState]::Stopped)
    {
        LogMsg 3 "Info : $($vm.vmName) is not in a stopped state - stopping VM"
        Stop-VM $vm.vmName -server $vm.hvServer -force -wait | out-null

        $v = Get-VM $vm.vmName -server $vm.hvServer
        if ($v.EnabledState -ne [VMState]::Stopped)
        {
            LogMsg 0 "Error: ResetVM is unable to stop VM $($vm.vmName). VM has been disabled"
            $vm.emailSummary += "Unable to stop VM.  VM was disabled and no tests run<br />"
            UpdateState $vm $Disabled
            return
        }
    }

    #
    # Reset the VM to a snapshot to put the VM in a known state.
    #
    $snapshotName = "ICABase"
    if ($vm.snapshotName)
    {
        $snapshotName = $vm.snapshotName
        LogMsg 9 "Info : $($vm.vmName) Over-riding default snapshotName to $snapshotName"
    }

    #
    # Find the snapshot we need and apply the snapshot
    #
    $snapshotFound = $false
    $snaps = Get-VMSnapshot $vm.vmName -server $vm.hvServer
    foreach($s in $snaps)
    {
        if ($s.ElementName -eq $snapshotName)
        {
            LogMsg 3 "Info : $($vm.vmName) is being reset to snapshot $($s.ElementName)"
            Restore-VMSnapshot $s -force -wait | out-null
            $snapshotFound = $true
            break
        }
    }

    #
    # Make sure the snapshot left the VM in a stopped state.
    #
    if ($snapshotFound )
    {
        #
        # If a VM is in the Suspended (Saved) state after applying the snapshot,
        # the following will handle this case
        #
        $v = Get-VM $vm.vmName -server $vm.hvServer
        if ($v.EnabledState -eq [VMState]::Suspended)
        {
            LogMsg 3 "Info : $($vm.vmName) - resetting to a stopped state after restoring a snapshot"
            Stop-VM $vm.vmName -server $vm.hvServer -force -wait | out-null
        }
    }
    else
    {
        LogMsg 0 "Warn : $($vm.vmName) does not have a snapshot named $snapshotName."
    }

    #
    # Update the state, and state transition timestamp,
    #
    UpdateState $vm $SystemDown
}


########################################################################
#
# DoStateMachine()
#
# Description:
#    This is the state engine for the LIS automation scripts.
#
#    Pre-Conditions
#        Actual VMs in a stopped state, or marked as Disabled in the
#        XmlElement representing the VM.
#
#    Post Conditions
#        All tests have completed execution on all VMs and the VMs
#        have been left in a stopped state.
#
# Parameters:
#    $xmlConfig : The parsed xml configuration file.
#
# Return:
#
########################################################################
function DoStateMachine([XML] $xmlConfig)
{
    LogMsg 9 "Info : Entering DoStateMachine()"

    $done = $false
    while(! $done)
    {
        $done = $true  # Assume we are done
        foreach( $vm in $xmlConfig.config.VMs.vm )
        {
            switch($vm.state)
            {
            $SystemDown
                {
                    DoSystemDown $vm $xmlConfig
                    $done = $false
                }

            $RunSetupScript
                {
                    DoRunSetupScript $vm $xmlConfig
                    $done = $false
                }

            $StartSystem
                {
                    DoStartSystem $vm $xmlConfig
                    $done = $false
                }

            $SystemStarting
                {
                    DoSystemStarting $vm $xmlConfig
                    $done = $false
                }

            $SlowSystemStarting
                {
                    DoSlowSystemStarting $vm $xmlConfig
                    $done = $false
                }

            $DiagNoseHungSystem
                {
                    DoDiagnoseHungSystem $vm $xmlConfig
                    $done = $false
                }

            $SystemUp
                {
                    DoSystemUp $vm $xmlConfig
                    $done = $false
                }

            $PushTestFiles
                {
                    DoPushTestFiles $vm $xmlConfig
                    $done = $false
                }

            $RunPreTestScript
                {
                    DoRunPreTestScript $vm $xmlConfig
                    $done = $false
                }

            $StartTest
                {
                    DoStartTest $vm $xmlConfig
                    $done = $false
                }

            $TestStarting
                {
                    DoTestStarting $vm $xmlConfig
                    $done = $false
                }

            $TestRunning
                {
                    DoTestRunning $vm $xmlConfig
                    $done = $false
                }

            $CollectLogFiles
                {
                    DoCollectLogFiles $vm $xmlConfig
                    $done = $false
                }

            $RunPostTestScript
                {
                    DoRunPostTestScript $vm $xmlConfig
                    $done = $false
                }

            $DetermineReboot
                {
                    DoDetermineReboot $vm $xmlConfig
                    $done = $false
                }

            $ShutdownSystem
                {
                    DoShutdownSystem $vm $xmlConfig
                    $done = $false
                }

            $ShuttingDown
                {
                    DoShuttingDown $vm $xmlConfig
                    $done = $false
                }

            $RunCleanupScript
                {
                    DoRunCleanUpScript $vm $xmlConfig
                    $done = $false
                }

            $ForceShutDown
                {
                    DoForceShutDown $vm $xmlConfig
                    $done = $false
                }

            $StartPS1Test
                {
                    DoStartPS1Test $vm $xmlConfig
                    $done = $false
                }

            $PS1TestRunning
                {
                    DoPS1TestRunning $vm $xmlConfig
                    $done = $false
                }

            $PS1TestCompleted
                {
                    DoPS1TestCompleted $vm $xmlConfig
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
                    LogMsg 0 "Error: State machine encountered an undefined state for VM $($vm.vmName), State = $($vm.state)"
                    $vm.currentTest = "done"
                    UpdateState $vm $ForceShutDown
                }
            }
        }
        Start-Sleep -m 100
    }

    LogMsg 5 "Info : DoStateMachine() exiting"
}


########################################################################
#
# DoSystemDown()
#
# Description:
#    Update the VMs currentTest.
#    Transition to RunSetupScript if the currentTest defines a setup script.
#    Otherwise, transition to StartSystem
#
#    Pre-Condition
#        A valid XmlElement representing the VM
#        A valid parsed copy of the XML file
#        The actual VM is in a stopped state.
#
#    Post Condition
#        Transition to one of the following states
#            StartSystem
#            RunSetupScript
#            ForceShutdown
#            Disabled
#
# Parameters:
#    $vm  : The XML object representing the VM
#
# Return:
#    None.
#
########################################################################
function DoSystemDown([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemDown received an invalid VM parameter"
        return
    }

    LogMsg 9 "Info : Entering DoSystemDown( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemDown received a null or invalid xmlData parameter - VM $($vm.vmName) disabled"
        $vm.emailSummary += "    DoSystemDown received a null xmlData parameter - VM disabled<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    #
    # Make sure the VM is stopped
    #
    $v = Get-VM $vm.vmName -server $vm.hvServer
    if ($v.EnabledState -ne [VMState]::Stopped)
    {
        LogMsg 0 "Error: $($vm.vmName) entered SystemDown in a non-stopped state`n       The VM will be disabled"
        $vm.emailSummary += "          SystemDown found the VM in a non-stopped state - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
        return
    }

    #
    # Update the VMs current test
    #
    #$nextTest = [string] (GetNextTest $vm $xmlData)
    #$vm.currentTest = $nextTest
    UpdateCurrentTest $vm $xmlData
    
    $iterationMsg = $null
    if ($vm.iteration -ne "-1")
    {
        $iterationMsg = " (iteration $($vm.iteration))"
    }
    LogMsg 0 "Info : $($vm.vmName) currentTest updated to $($vm.currentTest) ${iterationMsg}"

    if ($($vm.currentTest) -eq "done")
    {
        UpdateState $vm $Finished
    }
    else
    {
        $testData = GetTestData $vm.currentTest $xmlData
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
                        LogMsg 3 "Info : $($vm.vmName) - running setup script '${script}'"
 
                        if (-not (RunPSScript $vm $script $xmlData "Setup" $logfile))
                        {
                            #
                            # If the setup script fails, fail the test. If <OnError>
                            # is continue, continue on to the next test in the suite.
                            # Otherwise, terminate testing.
                            #
                            LogMsg 0 "Error: VM $($vm.vmName) setup script ${script} for test ${testName} failed"
                            $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Failed - setup script failed")
                            #$vm.emailSummary += ("    Test {0,-25} : {2}<br />" -f $($vm.currentTest), $iterationMsg, $completionCode)
                            if ($abortOnError)
                            {
                                $vm.currentTest = "done"
                                UpdateState $vm $finished
                                return
                            }
                            else
                            {
                                UpdateState $vm $SystemDown
                                return
                            }
                        }
                    }
                }
                else  # the older, single setup script syntax
                {
                    LogMsg 3 "Info : $($vm.vmName) - running single setup script '$($testData.setupScript)'"
            
                    if (-not (RunPSScript $vm $($testData.setupScript) $xmlData "Setup" $logfile))
                    {
                        #
                        # If the setup script fails, fail the test. If <OnError>
                        # is continue, continue on to the next test in the suite.
                        # Otherwise, terminate testing.
                        #
                        LogMsg 0 "Error: VM $($vm.vmName) setup script $($testData.setupScript) for test ${testName} failed"
                        #$vm.emailSummary += "    Test $($vm.currentTest) : Failed - setup script failed<br />"
                        $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Failed - setup script failed")
                    
                        if ($abortOnError)
                        {
                            $vm.currentTest = "done"
                            UpdateState $vm $finished
                            return
                        }
                        else
                        {
                            UpdateState $vm $SystemDown
                            return
                        }
                    }
                }
            }
            else
            {
                LogMsg 9 "INFO : $($vm.vmName) does not have setup script defined for test $($vm.currentTest)"
            }
            UpdateState $vm $StartSystem
        }
        else
        {
            LogMsg 0 "Error: No test data for test $($vm.currentTest) in the .xml file`n       $($vm.vmName) has been disabled"
            $vm.emailSummary += "          No test data found for test $($vm.currentTest)<br />"
            $vm.currentTest = "done"
            UpdateState $vm $Disabled
        }
    }
}


########################################################################
#
# DoRunSetupScript()
#
# Description:
#    Run any setup scripts the current test define.
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed copy of the test run's XML file.
#        The virtual machine is in a stopped state.
#        The current test defines a setup script.
#
#    Post Conditions
#        The setup script executed.
#        State transisiton to one of the following states
#            StartSystem
#            Finished
#            Disabled
#
# Parameters:
#    vm      - An XmlElement representing the actual virtual machine
#
#    xmlData - The parsed XML file for the current test run.
#
# Return:
#    None.  
#
########################################################################
function DoRunSetupScript([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunSetupScript() was passed an invalid VM object"
        return
    }

    LogMsg 9 "Info : DoRunSetupScript( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunSetupScript received a null or invalid xmlData parameter - terminating VM"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    #
    # Run setup script if one is specified
    #
    $testData = GetTestData $($vm.currentTest) $xmlData
    if ($testData -is [System.Xml.XmlElement])
    {
        if ($testData.setupScript)
        {
            LogMsg 3 "Info : $($vm.vmName) - starting setup script $($testData.setupScript)"
            
            $sts = RunPSScript $vm $($testData.setupScript) $xmlData "Setup"
            if (-not $sts)
            {
                #
                # Fail the test if setup script fails.  We're already in SystemDown state so no state transition is needed.
                #
                LogMsg 0 "Error: VM $($vm.vmName) setup script $($testData.setupScript) for test $($testData.testName) failed"
                $vm.emailSummary += "Test $($vm.currentTest) : Aborted<br />"
                $vm.currentTest = "done"
                UpdateState $vm $finished
            }
            else
            {
                UpdateState $vm $StartSystem
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) entered RunSetupScript state with no setup script defined for test $($vm.currentTest)"
            $vm.emailSummary += "Test $($vm.currentTest) : Aborted (corrupt setupScript data)<br />"
            $vm.currentTest = "done"
            UpdateState $vm $Finished
        }
    }
    else
    {
        LogMsg 0 "Error: $($vm.vmName) could not find test data for $($vm.currentTest)`n       The VM $($vm.vmName) will be disabled"
        $vm.emailSummary += "Test $($vm.currentTest) : Aborted (no test data)<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }
}


########################################################################
#
# DoStartSystem()
#
# Description:
#    Start the actual virtual machine the $vm XmlElement represents.
#
#    Pre-Conditions
#        A valid XmlElement that represents the actual virtual machine.
#        A parsed XML data file.
#        The actual VM in a stopped state.
#
#    Post Conditions
#        The actual virtual machine is in a HyperV running state.
#        The vm's Xmlelement transition to one of the following states:
#            SystemStarting
#            ShuttingDown
#            Disabled
#
# Parameters:
#    vm      - An XmlElement representing the actual virtual machine
#
#    xmlData - The parsed XML file for the current test run.
#
# Return:
#    None.  The VM's XmlElement has transitioned to a new state.
#
########################################################################
function DoStartSystem([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartSystem received an invalid VM object"
        return
    }
    
    LogMsg 9 "Info : DoStartSystem( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartSystem received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "    DoStartSystem received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    #
    # Make sure the VM is in the stopped state
    #
    $v = Get-VM $vm.vmName -server $vm.hvServer
    $hvState = $v.EnabledState
    if ($hvState -ne [VMState]::Stopped)
    {
        LogMsg 0 "Error: $($vm.vmName) entered $StartSystem when the VM was not is a stopped state"
        $vm.emailSummary += "    Entered a StartSystem state with VM in a non-stopped state<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ShutdownSystem
    }
        
    #
    # Start the VM and wait for the Hyper-V state to go to Running
    #
    LogMsg 6 "Info : $($vm.vmName) is being started"

    $vmToStart = Get-VM $vm.vmName -server $vm.hvServer
    Start-VM $vmToStart -server $vm.hvServer -wait | out-null
    
    $timeout = 180
    while ($timeout -gt 0)
    {
        #
        # Check if the VM is in the Hyper-v Running state
        #
        $v = Get-VM $vm.vmName -server $vm.hvServer
        if ($($v.EnabledState) -eq [VMState]::Running)
        {
            break
        }

        start-sleep -seconds 1
        $timeout -= 1
    }

    #
    # Check if we timed out waiting to reach the Hyper-V Running state
    #
    if ($timeout -eq 0)
    {
        LogMsg 0 "Warn : $($vm.vmName) never reached Hyper-V status Running - timed out`n       Terminating test run."
        $vm.emailSummary += "    Never entered running state. Terminating test run<br />"
        
        $v = Get-VM $vm.vmName -server $vm.hvServer
        Stop-VM $v -server $vm.hvServer | out-null
        $vm.currentTest = "done"
        UpdateState $vm $ShuttingDown
    }
    else
    {
        UpdateState $vm $SystemStarting
    }
}


########################################################################
#
# DoSystemStarting()
#
# Description:
#    Check for access to port 22 (sshd) on the VM.  Once Sshd
#    is accessable, we can send work to the VM.
#
#    Transition to state SystemUp when port 22 is accessable.
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed XML test data file.
#        The actual in a HyperV running state.
#
#    Post Conditions
#        The actual virtual machine is in a HyperV running state.
#        The vm's Xmlelement transition to one of the following states:
#            SystemUp
#            SystemSlowStarting
#            ForceShutdown
#
# Parameters:
#    $vm      : The XML object representing the VM.
#
#    $xmlData : The parsed XML test file.
#
# Return:
#    None.
#
########################################################################
function DoSystemStarting([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemStarting received an invalid VM object"
        return
    }

    LogMsg 9 "Info : Entering DoSystemStarting( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemStarting was passed a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoSystemStarting received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $v = Get-VM $vm.vmName -server $vm.hvServer
    if ($v.EnabledState -ne [VMState]::Running)
    {
        LogMsg 0 "Error: $($vm.vmName) SystemStarting entered state without being in a HyperV Running state - disabling VM"
        $vm.emailSummary += "    SystemStarting entered without being in a HyperV Running state - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = 600

    if ($vm.timeouts.systemStartingTimeout)
    {
        $timeout = $vm.timeouts.systemStartingTimeout
    }
 
    if ( (HasItBeenTooLong $vm.stateTimestamp $timeout) )
    {
        UpdateState $vm $SlowSystemStarting
    }
    else
    {
        #
        # See if the SSH port is accepting connections
        #
        $sts = TestPort $vm.ipv4 -port 22 -timeout 5
        if ($sts)
        {
            UpdateState $vm $SystemUp
        }
    }
}


########################################################################
#
# DoSlowSystemStarting()
#
# Description:
#    Continue checking for access to port 22 on the VM.
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed XML test data file.
#        The actual in a HyperV running state.
#
#    Post Conditions
#        The actual virtual machine is in a HyperV running state.
#        The vm's Xmlelement transition to one of the following states:
#            SystemUp
#            DiagnoseSystem
#            ForceShutdown
#
# Parameters:
#    $vm      : The XML object representing the VM.
#
#    $xmlData : The parsed XML test file.
#
# Return:
#    None.
#
########################################################################
function DoSlowSystemStarting([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSlowSystemStarting received an invalid vm object"
        return
    }

    LogMsg 9 "Info : Entering DoSlowSystemStarting()"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSlowSystemStarting was passed a null xmlData - disabling VM"
        $vm.emailSummary += "DoSlowSystemStarting recieved a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = 1200
    if ($vm.timeouts.slowSystemStartingTimeout)
    {
        $timeout = $vm.timeouts.slowSystemStartingTimeout
    }

    if ( (HasItBeenTooLong $vm.stateTimestamp $timeout) )
    {
        UpdateState $vm $DiagnoseHungSystem
    }
    else
    {
        $sts = TestPort $vm.ipv4 -port 22 -timeout 5
        if ($sts)
        {
            UpdateState $vm $SystemUp
        }
    }
}


########################################################################
#
# DiagnoseHungSystem()
#
# Description:
#     Currently, just terminate tests on the VM.
#
#     If timeout, abort.
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#
########################################################################
function DoDiagnoseHungSystem([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoDiagnoseHungSystem received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : Entering DoDiagnoseHungSystem()"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoDiagnoseHungSystem was passed a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoDiagnoseHungSystem received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # Current behavior for this function is defined to just log some messages
    # and then try to stop the VM
    #
    LogMsg 0 "Error: $($vm.vmName) never booted for test $($vm.currentTest)"
    LogMsg 0 "Error: $($vm.vmName) terminating test run."
    $vm.emailSummary += "    Unsuccessful boot for test $($vm.currentTest)<br />"
    
    #
    # currently, we do not do anything other than stopping the VM
    #    
    $vm.currentTest = "done"
    UpdateState $vm $ForceShutdown
}


########################################################################
#
# DoSystemUp()
#
# Description:
#    Send an exit command to VM to accept SSH prompt for server key
#    if this is the first time this host has connect to the VM.
#
#    Set the time on the virtual machine.
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed XML test data file.
#        The actual virtual machine in a HyperV running state.
#        The virtual is listening on port 22 (SSH)
#
#    Post Conditions
#        The actual virtual machine is in a HyperV running state.
#        The time on the virtual machine has been updated.
#        The vm's Xmlelement transition to one of the following states:
#            PushTestFiles
#            DetermineReboot
#            ForceShutdown
#
# Parameters:
#    $vm  : The XML object representing the VM
#
# Return:
#    None.
#
########################################################################
function DoSystemUp([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemUp received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoSystemUp($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemUp received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoSystemUp received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

    #
    # The first time we SSH into a VM, SSH will prompt to accept the server key.
    # Send a "no-op command to the VM and assume this is the first SSH connection,
    # so pipe a 'y' respone into plink
    #
    echo y | bin\plink -i ssh\${sshKey} root@${hostname} exit

    #
    # Determine the VMs OS
    #
    $os = (GetOSType $vm).ToString()

    #
    # Update the time on the Linux VM
    #
    $dateTimeCmd = GetOSDateTimeCmd $vm
    if ($dateTimeCmd)
    {
        #$linuxDateTime = [Datetime]::Now.ToString("MMddHHmmyyyy")
        #LogMsg 3 "Info : $($vm.vmName) Updating time on the VM (${dateTimeCmd})."
        #if (-not (SendCommandToVM $vm "$dateTimeCmd") )
        #{
        #    LogMsg 0 "Error: $($vm.vmName) could not update time"
        #    $vm.emailSummary += "    Unable to update time on VM - test aborted<br />"
        #    $vm.testCaseResults = "False"
        #    UpdateState $vm $DetermineReboot
        #}
        #else
        #{
            UpdateState $vm $PushTestFiles
        #}
    }
    else
    {
        UpdateState $vm $PushTestFiles
    }
}


########################################################################
#
# DoPushTestFiles()
#
# Description:
#    Push the test files to the VM
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed XML test data file.
#        The actual in a HyperV running state.
#        The VM is listening on the network and has the correct time.
#
#    Post Conditions
#        The file required to run a test have been pushed to the VM.
#        The vm's Xmlelement transition to one of the following states:
#            StartTest
#            DetermineReboot
#            ForceShutdown
#
# Parameters:
#    $vm      : The XML object representing the VM
#    $xmlData : The parsed .xml file
#
# Return:
#    None.
#
########################################################################
function DoPushTestFiles([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPushTestFiles received an invalid null vm parameter"
        return
    }

    LogMsg 9 "Info : DoPushTestFiles($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPushTestFiles received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoPushTestFiles received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # Get test specific information
    #
    LogMsg 6 "Info : $($vm.vmName) Getting test data for current test $($vm.currentTest)"
    $testData = GetTestData $($vm.currentTest) $xmlData
    if ($null -eq $testData)
    {
        LogMsg 0 "Error: $($vm.vmName) no test named $($vm.currentTest) was found in xml file"
        $vm.emailSummary += "    No test named $($vm.currentTest) was found - test aborted<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    #
    # If the test script is a powershell script, transition to the appropriate state
    #
    $testScript = $($testData.testScript).Trim()
    if ($testScript -eq $null)
    {
        LogMsg 0 "Error: $($vm.vmName) test case $($vm.currentTest) does not have a testScript"
        $vm.emailSummary += "    Test case $($vm.currentTest) does not have a testScript.<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }
   
    #
    # Push the files to the VM as specified in the <files> tag.
    #
    LogMsg 3 "Info : $($vm.vmName) Pushing files and directories to VM"
    if ($testData.files)
    {
        $files = ($testData.files).split(",")
        foreach ($f in $files)
        {
            $testFile = $f.trim()
            if ($testFile.EndsWith(".ps1"))
            {
                continue
            }
            if (-not (SendFileToVM $vm $testFile) )
            {
                LogMsg 0 "Error: $($vm.vmName) error pushing file '$testFile' to VM"
                $vm.emailSummary += "    Unable to push test file '$testFile' to VM<br />"
                $vm.testCaseResults = "False"
                UpdateState $vm $DetermineReboot
                return
            }
            if($testFile.EndsWith(".sh"))
            {
                #
                # Make sure the test files has Unix EOL
                #
                $testfile = $testfile.Replace("/","\")
                    
                $pushfile = $testfile.Split("`\")
               
                $count = $pushfile.count
                   
                $testFile = $pushfile[$count-1]
               
                LogMsg 3 "Info : $($vm.vmname) converting EOL for file $testFile"
                $dos2unixCmd = GetOSDos2UnixCmd $vm $testFile
                #$dos2unixCmd = "dos2unix -q $testScript"
                if ($dos2unixCmd)
                {
                    if (-not (SendCommandToVM $vm "${dos2unixCmd}") )
                    {
                        LogMsg 0 "Error: $($vm.vmName) unable to set EOL on test script file $testFile"
                        $vm.emailSummary += "    Unable to set EOL on file $testFile<br />"
                        $vm.testCaseResults = "False"
                        UpdateState $vm $DetermineReboot
                        return
                    }
                }
                else
                {
                    LogMsg 0 "Error: $($vm.vmName) cannot create dos2unix command for ${testFile}"
                    $vm.emailSummary += "    Unable to create dos2unix command for $testScript<br />"
                    $vm.testCaseResults = "False"
                    UpdateState $vm $DetermineReboot
                    return
                }
                #
                # Set the test script execute bit
                #
                LogMsg 3 "Info : $($vm.vmName) setting execute bit on $testFile"
                if (-not (SendCommandToVM $vm "chmod 755 $testFile") )
                {
                    LogMsg 0 "$($vm.vmName) unable to set execute bit on test script $testFile"
                    $vm.emailSummary += "    Unable to set execute bit on test script $testFile<br />"
                    $vm.testCaseResults = "False"
                    UpdateState $vm $DetermineReboot
                    return
                }
            }
        }
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
    
    if ($xmlData.config.global.testParams -or $testdata.testParams -or $vm.testParams)
    {
        #
        # First, add any global testParams
        #
        if ($xmlData.config.global.testParams)
        {
            LogMsg 9 "Info : $($vm.vmName) Adding glogal test params"
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
            LogMsg 9 "Info : $($vm.vmName) Adding testparmas for test $($testData.testName)"
            foreach ($param in $testdata.testparams.param)
            {
                ($param) | out-file -encoding ASCII -append -filePath $constFile
            }
        }
        
        #
        # Now, add VM specific testParams
        #
        if ($vm.testparams)
        {
            LogMsg 9 "Info : $($vm.vmName) Adding VM specific params"
            foreach ($param in $vm.testparams.param)
            {
                ($param) | out-file -encoding ASCII -append -filePath $constFile
            }
        }
    }

    #
    # Add the iteration information if test case is being iterated
    #
    if ($vm.iteration -ne "-1")
    {
        "iteration=$($vm.iteration)" | out-file -encoding ASCII -append -filePath $constFile
        
        if ($testData.iterationParams)
        {
            $iterationParam = GetIterationParam $vm $xmlData
                    
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
        LogMsg 3 "Info : $($vm.vmName) Pushing constants file $constFile to VM"
        if (-not (SendFileToVM $vm $constFile $constFile) )
        {
            LogMsg 0 "Error: $($vm.vmName) cannot push $constFile to $($vm.vmName)"
            $vm.emailSummary += "    Cannot pushe $constFile to VM<br />"
            $vm.testCaseResults = "False"
            UpdateState $vm $DetermineReboot
            return
        }
        
        #
        # Convert the end of line characters in the constants file
        #
        $dos2unixCmd = GetOSDos2UnixCmd $vm $constFile
        #$dos2unixCmd = "dos2unix -q ${constFile}"

        if ($dos2unixCmd)
        {
            LogMsg 3 "Info : $($vm.vmName) converting EOL for file $constFile"
            if (-not (SendCommandToVM $vm "${dos2unixCmd}") )
            {
                LogMsg 0 "Error: $($vm.vmName) unable to convert EOL on file $constFile"
                $vm.emailSummary += "    Unable to convert EOL on file $constFile<br />"
                $vm.testCaseResults = "False"
                UpdateState $vm $DetermineReboot
                return
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) cannot create dos2unix command for ${constFile}"
            $vm.emailSummary += "    Unable to create dos2unix command for ${constFile}<br />"
            $vm.testCaseResults = "False"
            UpdateState $vm $DetermineReboot
            return
        }
        
        del $constFile -ErrorAction:SilentlyContinue
    }
    
    if ($testScript.EndsWith(".ps1"))
    {
        UpdateState $vm $StartPS1Test
        return
    }
   
    if ($($testData.preTest) )
    {
        UpdateState $vm $RunPreTestScript
    }
    else
    {
        UpdateState $vm $StartTest
    }
}


########################################################################
#
# DoRunPreTestScript()
#
########################################################################
function DoRunPreTestScript([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunPreTestScript() was passed an invalid VM object"
        return
    }

    LogMsg 9 "Info : DoRunPreTestScript( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunPreTestScript received a null or invalid xmlData parameter - terminating VM"
    }
    else
    {
        #
        # Run pretest script if one is specified
        #
        $testData = GetTestData $($vm.currentTest) $xmlData
        if ($testData -is [System.Xml.XmlElement])
        {
            if ($testData.preTest)
            {
                LogMsg 3 "Info : $($vm.vmName) - starting preTest script $($testData.setupScript)"
                
                $sts = RunPSScript $vm $($testData.preTest) $xmlData "PreTest"
                if (-not $sts)
                {
                    LogMsg 0 "Error: VM $($vm.vmName) preTest script for test $($testData.testName) failed"
                }
            }
            else
            {
                LogMsg 0 "Error: $($vm.vmName) entered RunPreTestScript with no preTest script defined for test $($vm.currentTest)"
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) could not find test data for $($vm.currentTest)"
        }
    }
    
    UpdateState $vm $StartTest
}


########################################################################
#
# DoStartTest()
#
# Description:
#    Start the test running on the VM.
#    - Create the runtest.sh script
#    - Push runtest.sh to the VM
#    - Set the execute bit on runtest.sh
#    - Make sure the ATD is running on the VM
#    - Submit runtest.sh
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed XML test data file.
#        The actual in a HyperV running state.
#        The VM is listening on the network and has the correct time.
#        The test case files have been copied to the VM.
#
#    Post Conditions
#        The runtest.sh script has been submitted to the ATD on the VM
#        The vm's Xmlelement transition to one of the following states:
#            TestStarting
#            DetermineReboot
#            ForceShutdown
#
# Parameters:
#    $vm      : The XML object representing the VM
#    $xmlData : The parsed .xml file
#
# Return:
#    None.
#
########################################################################
function DoStartTest([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartTest received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoStartTest($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartTest received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoStartTest received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # Create a shell script to run the actual test script.
    # This is a hack so the test script output can be directed into a specified log file.
    #
    del runtest.sh -ErrorAction "SilentlyContinue"
    
    #
    # Create the runtest.sh script, push it to the VM, set the execute bit, then delete local copy
    #
    $testData = GetTestData $vm.currentTest $xmlData
    if (-not $testData)
    {
        LogMsg 0 "Error: $($vm.vmName) cannot fine test data for test '$($vm.currentTest)"
        $vm.emailSummary += "    Cannot fine test data for test '$($vm.currentTest)<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }
    
    #"./$($testData.testScript) &> $($vm.currentTest).log " | out-file -encoding ASCII -filepath runtest.sh
    $runCmd = GetOSRunTestCaseCmd $($vm.os) $($testData.testScript) "$($vm.currentTest).log"
    if (-not $runCmd)
    {
        LogMsg 0 "Error: $($vm.vmName) unable to create runtest.sh"
        $vm.emailSummary += "    Unable to create runtest.sh<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    $runCmd | out-file -encoding ASCII -filepath runtest.sh
    LogMsg 3 "Info : $($vm.vmName) pushing file runtest.sh"
    if (-not (SendFileToVM $vm "runtest.sh" "runtest.sh") )
    {
        LogMsg 0 "Error: $($vm.vmName) cannot copy runtest.sh to VM"
        $vm.emailSummary += "    Cannot copy runtest.sh to VM<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    del runtest.sh -ErrorAction:SilentlyContinue

    LogMsg 3 "Info : $($vm.vmName) setting the execute bit on runtest.sh"
    if (-not (SendCommandToVM $vm "chmod 755 runtest.sh") )
    {
        LogMsg 0 "Error: $($vm.vmName) cannot set execute bit on runtest.sh"
        $vm.emailSummary += "    Cannot set execute bit on runtest.sh<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    $dos2unixCmd = GetOSDos2UnixCmd $vm "runtest.sh"
    #$dos2unixCmd = "dos2unix -q runtest.sh"
    if (-not $dos2unixCmd)
    {
        LogMsg 0 "Error: $($vm.vmName) cannot create dos2unix command for runtest.sh"
        $vm.emailSummary += "    Cannot create dos2unix command for runtest.sh<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    LogMsg 3 "Info : $($vm.vmName) correcting the EOL for runtest.sh"
    if (-not (SendCommandToVM $vm "${dos2unixCmd}") )
    {
        LogMsg 0 "Error: $($vm.vmName) Unable to correct the EOL on runtest.sh"
        $vm.emailSummary += "    Unable to correct the EOL on runtest.sh<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    #
    # Make sure atd daemon is running on the remote machine
    #
    LogMsg 3 "Info : $($vm.vmName) enabling atd daemon"
    #if (-not (SendCommandToVM $vm "/etc/init.d/atd restart") )
    if (-not (StartOSAtDaemon $vm))
    {
        LogMsg 0 "Error: $($vm.vmName) Unable to start atd on VM"
        $vm.emailSummary += "    Unable to start atd on VM<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }
    else{
        LogMsg 0 "Info : $($vm.vmName) Started atd daemon on VM"
    }

    #
    # Submit the runtest.sh script to the at queue
    #
    SendCommandToVM $vm "rm -f state.txt"
    LogMsg 3 "Info : $($vm.vmName) submitting job runtest.sh"
    if (-not (SendCommandToVM $vm "at -f runtest.sh now") )
    {
        LogMsg 0 "Error: $($vm.vmName) unable to submit runtest.sh to atd on VM"
        $vm.emailSummary += "    Unable to submit runtest.sh to atd on VM<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    UpdateState $vm $TestStarting
}


########################################################################
#
# DoTestStarting()
#
# Description:
#    Check for the Test VM to create the state.txt file.
#    If file exists, transition to TestRunning.
#    Otherwise, leave state TestStarting.
#
#    If timeout, terminate current test.
#
#    Pre-Conditions
#        A valid XmlElement representing the actual virtual machine.
#        A parsed XML test data file.
#        The actual in a HyperV running state.
#        The VM is listening on the network and has the correct time.
#        The test case files have been copied to the VM.
#        The runtest.sh script has been submitted to the ATD queue on the VM.
#
#    Post Conditions
#        The test case script has started and created the state.txt file on the VM.
#        The vm's Xmlelement transition to one of the following states:
#            TestRunning
#            DetermineReboot
#            ForceShutdown
#
# Parameters:
#    $vm      : The XML object representing the VM
#    $xmlData : The parsed .xml file
#
# Return:
#    None.
#
########################################################################
function DoTestStarting([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoTestStarting received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoTestStarting($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoTestStarting received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoTestStarting received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #$hostname = $vm.ipv4
    #$sshKey = $vm.sshKey

    $timeout = 600
    if ($vm.timeouts.testStartingTimeout)
    {
        $timeout = $vm.timeouts.testStartingTimeout
    }

    if ( (HasItBeenTooLong $vm.stateTimestamp $timeout) )
    {
        LogMsg 0 "Error: $($vm.vmName) time out starting test $($vm.currentTest)"
        $vm.emailSummary += "    time out starting test $($vm.currentTest)<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $DetermineReboot
        return
    }

    $stateFile = "state.txt"
    del $stateFile -ErrorAction "SilentlyContinue"
    if ( (GetFileFromVM $vm $stateFile ".") )
    {
        if ( (test-path $stateFile) )
        {
            UpdateState $vm $TestRunning
        }
    }
    del $stateFile -ErrorAction "SilentlyContinue"
}


########################################################################
#
# DoTestRunning()
#
# Description:
#     Get a copy of the state.txt file from the VM.
#     If state file contains TestCompleted
#         transition to state CollectLogFiles
#     If state file contains TestAborted
#         transition to state TestAborted
#
#     If timeout, transition to TestAborted.
#     Note: this timeout is defined in the .xml file.
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#     none.
#
########################################################################
function DoTestRunning([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoTestRunning received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoTestRunning($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoTestRunning received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoTestRunning received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = 10800
    $testData = GetTestData $vm.currentTest $xmlData
    if ($testData -and $testData.timeout)
    {
        $timeout = $testData.timeout
    }

    if ( (HasItBeenTooLong $vm.stateTimestamp $timeout) )
    {
        LogMsg 0 "Error: $($vm.vmName) time out running test $($vm.currentTest)"
        $vm.emailSummary += "    time out running test $($vm.currentTest)<br />"
        $vm.testCaseResults = "False"
        UpdateState $vm $CollectLogFiles
        return
    }

    $stateFile = "state.txt"

    del $stateFile -ErrorAction "SilentlyContinue"
    
    if ( (GetFileFromVM $vm $stateFile ".") )
    {
        if (test-path $stateFile)
        {
            $vm.testCaseResults = "Aborted"
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                if ($contents -eq $TestRunning)
                {
                    return
                }
                elseif ($contents -eq $TestCompleted)
                {
                    $vm.testCaseResults = "Success"
                    UpdateState $vm $CollectLogFiles
                }
                elseif ($contents -eq $TestAborted)
                {
                    AbortCurrentTest $vm "$($vm.vmName) Test $($vm.currentTest) aborted. See logfile for details"
                }
                elseif($contents -eq $TestFailed)
                {
                    AbortCurrentTest $vm "$($vm.vmName) Test $($vm.currentTest) failed. See logfile for details"
                    $vm.testCaseResults = "Failed"
                }
                else
                {
                    AbortCurrentTest $vm "$($vm.vmName) Test $($vm.currentTest) has an unknown status of '$($contents)'"
                }
                
                del $stateFile -ErrorAction "SilentlyContinue"
            }
            else
            {
                LogMsg 6 "Warn : $($vm.vmName) state file is empty"
            }
        }
        else
        {
            LogMsg 0 "Warn : $($vm.vmName) ssh reported success, but state file was not copied"
        }
    }
    else
    {
        LogMsg 0 "Warn : $($vm.vmName) unable to pull state.txt from VM."
    }
}


########################################################################
#
# DoCollectLogFiles()
#
# Description:
#     Collect log file from the VM. Update th e-mail summary
#     with the test results. Set the transition time.  Finally
#     transition to FindNextAction to look at OnError, NoReboot,
#     and our current state to determine the next action.
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#     none.
#
########################################################################
function DoCollectLogFiles([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoCollectLogFiles received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoCollectLogFiles($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoCollectLogFiles received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoCollectLogFiles received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $currentTest = $vm.currentTest
    $iterationNum = $null
    if ($vm.iteration -ne "-1")
    {
        $iterationNum = $($vm.iteration)
    }
    $logFilename = "$($vm.vmName)_${currentTest}_${iterationNum}.log"
    $summaryLog = "$($vm.vmName)_summary.log"

    #
    # Update the e-mail summary
    #
    $completionCode = "Aborted"
    if ( ($($vm.testCaseResults) -eq "Success") )
    {
        $completionCode = "Success"
    }
    elseif ( ($($vm.testCaseResults) -eq "Failed") )
    {
        $completionCode = "Failed"
    }
    

    $iterationMsg = $null
    if ($vm.iteration -ne "-1")
    {
        $iterationMsg = "($($vm.iteration))"
    }
    #$vm.emailSummary += "    Test $($vm.currentTest) $iterationMsg : $completionCode.<br />"
    $vm.emailSummary += ("    Test {0,-25} : {2}<br />" -f $($vm.currentTest), $iterationMsg, $completionCode)
    
    #
    # Collect test results
    #
    LogMsg 4 "Info : $($vm.vmName) collecting logfiles"
    if (-not (GetFileFromVM $vm "${currentTest}.log" "${testDir}\${logFilename}") )
    {
        LogMsg 0 "Error: $($vm.vmName) DoCollectLogFiles() is unable to collect ${logFilename}"
    }

    #
    # Test case may optionally create a summary.log.
    #
    del $summaryLog -ErrorAction "SilentlyContinue"
    GetFileFromVM $vm "summary.log" .\${summaryLog}
    if (test-path $summaryLog)
    {
        $content = Get-Content -path $summaryLog
        foreach ($line in $content)
        {
            $vm.emailSummary += "          $line<br />"
        }
        del $summaryLog
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
            $dstFile = "$($vm.vmName)_${currentTest}_${file}"
            if (-not (GetFileFromVM $vm $file "${testDir}\${dstFile}") )
            {
                LogMsg 0 "Warn : $($vm.vmName) cannot copy '${file}' from VM"
            }
        }
    }

    #
    # Also delete state.txt from the VM
    #
    SendCommandToVM $vm "rm -f state.txt"
    
    LogMsg 0 "Info : $($vm.vmName) Status for test $currentTest $iterationMsg = $completionCode"

    if ( $($testData.postTest) )
    {
        UpdateState $vm $RunPostTestScript
    }
    else
    {
        UpdateState $vm $DetermineReboot
    }
}


########################################################################
#
# DoRunPostTestScript()
#
########################################################################
function DoRunPostTestScript([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        # This should never occur
        LogMsg 0 "Error: DoRunPostScript() was passed an invalid VM object"
        return
    }

    LogMsg 9 "Info : DoRunPostScript( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunPostTestScript received a null or invalid xmlData parameter - terminating VM"
        $vm.currentTest = "done"
        UpdateState $vm $DetermineReboot
    }

    #
    # Run postTest script if one is specified
    #
    $testData = GetTestData $($vm.currentTest) $xmlData
    if ($testData -is [System.Xml.XmlElement])
    {
        if ($testData.postTest)
        {
            LogMsg 3 "Info : $($vm.vmName) - starting postTest script $($testData.postTest)"
            
            $sts = RunPSScript $vm $($testData.postTest) $xmlData "PostTest"
            if (-not $sts)
            {
                LogMsg 0 "Error: VM $($vm.vmName) postTest script for test $($testData.testName) failed"
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) entered RunPostTestScript with no postTest script defined for test $($vm.currentTest)"
        }
    }
    else
    {
        LogMsg 0 "Error: $($vm.vmName) could not find test data for $($vm.currentTest)"
    }
    
    UpdateState $vm $DetermineReboot
}


########################################################################
#
# DoDetermineReboot()
#
# Description:
#     Look at OnError, NoReboot, and our current state to determine
#     what our next state should be.
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#
########################################################################
function DoDetermineReboot([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoDetermineReboot received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoDetermineReboot($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoDetermineReboot received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoDetermineReboot received a null xmlData parameter - disabling VM"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $nextTest = GetNextTest $vm $xmlData
    $testData = GetTestData $vm.currentTest $xmlData
    $testResults = $false
    
    if ( ($($vm.testCaseResults) -eq "Success") -or ($($vm.testCaseResults) -eq "True") )
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
    # setting current test to "done" so the SystemDown state will not run any
    # additional tests.
    #
    $nextState = "undefined"

    if ($testResults)
    {
        # Test was successful, so we don't care about <onError>
        if ($noReboot)
        {
            if ($nextTest -eq "done")
            {
                # Test successful, no reboot, no more tests to run
                $nextState = $ShutDownSystem
            }
            else
            {
                # Test successful, no reboot, more tests to run
                $nextState = $SystemUp
            }
        }
        else # reboot
        {
            # Test successful, reboot required
            $nextState = $ShutDownSystem
        }
    }
    else # current test failed
    {
        if ($continueOnError)
        {
            if ($noReboot)
            {
                if ($nextTest -eq "done")
                {
                    # Test failed, continue on error, no reboot, no more tests to run
                    $nextState = $ShutDownSystem
                }
                else
                {
                    # Test failed, continue on error, no reboot, more tests to run
                    $nextState = $SystemUp
                }
            }
            else
            {
                # Test failed, continue on error, reboot
                $nextState = $ShutDownSystem
            }
        }
        else # abort on error
        {
            # Test failed, abort on error
            $nextState = $ShutDownSystem
        }
    }
    
    switch ($nextState)
    {
    $SystemUp
        {
            if ($($testData.cleanupScript))
            {
                LogMsg 0 "Warn : $($vm.vmName) The <NoReboot> flag prevented running cleanup script for test $($testData.testName)"
            }
            
            #$nextTest = GetNextTest $vm $xmlData
            #$vm.currentTest = [string] $nextTest
            UpdateCurrentTest $vm $xmlData

            $iterationMsg = $null
            if ($vm.iteration -ne "-1")
            {
                $iterationMsg = "(iteration $($vm.iteration))"
            }
            LogMsg 0 "Info : $($vm.vmName) currentTest updated to $($vm.currentTest) ${iterationMsg}"

            if ($vm.currentTest -eq "done")
            {
                UpdateState $vm $ShutDownSystem
            }
            else
            {
                UpdateState $vm $SystemUp

                $nextTestData = GetTestData $nextTest $xmlData
                if ($($nextTestData.setupScript))
                {
                    LogMsg 0 "Warn : $($vm.vmName) The <NoReboot> flag prevented running setup script for test $nextTest"
                }
            }
        }
    $ShutDownSystem
        {
            UpdateState $vm $ShutDownSystem
        }
    default
        {
            LogMsg 0 "Error: $($vm.vmName) DoDetermineReboot Inconsistent next state: $nextState"
            UpdateState $vm $ShutDownSystem
            $vm.currentTest = "done"    # don't let the VM continue
        }
    }
}


########################################################################
#
# DoShutdownSystem
#
#
########################################################################
function DoShutdownSystem([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoShutdownSystem received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoShutdownSystem($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoShutdownSystem received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoShutdownSystem received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    ShutDownVM $vm
    UpdateState $vm $ShuttingDown
            
}


########################################################################
#
# DoShuttingDown()
#
# Description:
#     Check for Hyper-v status to go to Stopped (3)
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#     none.
#
########################################################################
function DoShuttingDown([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoShuttingDown received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoShuttingDown($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoShuttingDown received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoShuttingDown received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = 400
    if ($vm.timeouts.shuttingDownTimeout)
    {
        $timeout = $vm.timeouts.shuttingDownTimeout
    }
   
    if ( (HasItBeenTooLong $vm.stateTimestamp $timeout) )
    {
        UpdateState $vm $ForceShutDown
    }

    #
    # If vm is stopped, update its state
    #
    $v = Get-VM $vm.vmName -server $vm.hvServer
    if ($($v.EnabledState) -eq [VMState]::Stopped)
    {
        #
        # Check if we need to run a cleanup script
        #
        $currentTest = GetTestData $($vm.currentTest) $xmlData
        if ($currentTest -and $currentTest.cleanupScript)
        {
            UpdateState $vm $RunCleanUpScript
        }
        else
        {
            UpdateState $vm $SystemDown
        }
    }
    
}


########################################################################
#
# DoRunCleanUpScript()
#
# Description:
#    Run the cleanup script for the current test case.
#
# Parameters:
#    $vm
#
#    $xmlData
#
# Return:
#    none.
#
########################################################################
function DoRunCleanUpScript($vm, $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunCleanupScript received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoRunCleanupScript($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunCleanupScript received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoRunCleanupScript received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # We should never be called unless the VM is stopped
    #
    $v = Get-VM $vm.vmName -server $vm.hvServer
    if ($v.EnabledState -ne [VMState]::Stopped)
    {
        LogMsg 0 "Error: $($vm.vmName) is not stopped to run cleanup script for test $($vm.currentTest) - terminating tests"
        LogMsg 0 "Error: The VM may be left in a running state."
        $vm.emailSummay += "VM not in a stopped state to run cleanup script - tests terminated<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
        return
    }

    #
    # Run cleanup script of one is specified
    #
    $currentTestData = GetTestData $($vm.currentTest) $xmlData
    if ($currentTestData -is [System.Xml.XmlElement] -and $currentTestData.cleanupScript)
    {
        LogMsg 3 "Info : $($vm.vmName) running cleanup script $($currentTestData.cleanupScript) for test $($currentTestData.testName)"
        LogMsg 8 "Info : RunPSScript $($vm.vmName) $($currentTestData.cleanupScript) xmlData"
        
        $sts = RunPSScript $vm $($currentTestData.cleanupScript) $xmlData "Cleanup"
        if (! $sts)
        {
            #
            # Do not terminate test if cleanup script fails.  Just log a message and continue...
            #
            LogMsg 0 "Error: $($vm.vmName) cleanup script $($currentTestData.cleanupScript) for test $($currentTestData.testName) failed"
        }
    }
    else
    {
        LogMsg 0 "Error: $($vm.vmName) entered RunCleanupScript state when test $($vm.currentTest) does not have a cleanup script"
        $vm.emailSummary += "Entered RunCleanupScript but test does not have a cleanup script<br />"
    }

    UpdateState $vm $SystemDown
}


########################################################################
#
# DoForceShutDown()
#
# Description:
#     Check for Hyper-v status to go to Stopped (3)
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#     none.
#
########################################################################
function DoForceShutDown([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoForceShutdown received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoForceShutdown($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoForceShutdown received a null or invalid xmlData parameter - disabling VM"
        LogMsg 0 "       $($vm.vmName) may be left in a running state"
        $vm.emailSummary += "DoForceShutdown received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
        return
    }

    $timeout = 180
    if ($vm.timeouts.shuttingDownTimeout)
    {
        $timeout = $vm.timeouts.shuttingDownTimeout
    }

    $nextState = $SystemDown
    $currentTest = GetTestData $($vm.currentTest) $xmlData
    if ($currentTest -and $currentTest.cleanupScript)
    {
        $nextState = $RunCleanupScript
    }

    $v = Get-VM $vm.vmName -server $vm.hvServer
    if ( $($v.EnabledState) -eq [VMState]::Stopped )
    {
        UpdateState $vm $nextState
    }
    else
    {
        #
        # Try to force the VM to a stopped state
        #
        $v = Get-VM $vm.vmName -server $vm.hvServer
        Set-VMState -vm $v -state 3 # Set-VMState requires the integer value, not the enumerated [VMState]::Stopped value
        
        while ($timeout -gt 0)
        {
            $v = Get-VM $vm.vmName -server $vm.hvServer
            if ( $($v.EnabledState) -eq [VMState]::Stopped )
            {
                UpdateState $vm $nextState
                break
            }
            else
            {
                $timeout -= 1
                Start-Sleep -S 1
            }
        }
    }
            
    if ($($vm.state) -ne $nextState)
    {
        LogMsg 0 "Error: $($vm.vmName) could not be forced to a stoped state."
        LogMsg 0 "Error: the vm may be left in a running state"
        $vm.emailSummary += "$($vm.vmName) could not be forced into a stopped state.<br />"
        $vm.emailSummary += "The VM may be left in a running state!<br />"
        UpdateState $vm $Disabled
    }
}


########################################################################
#
# DoFinished()
#
# Description:
#     Currently there is no work for this state.
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#
########################################################################
function DoFinished([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    LogMsg 11 "Info : DoFinished( $($vm.vmName), xmlData )"
    LogMsg 11 "Info :   timestamp = $($vm.stateTimestamp))"
    LogMsg 11 "Info :   Test      = $($vm.currentTest))"
    
    # Currently, nothing to do...
}



########################################################################
#
# DoStartPS1Test()
#
# Description:
#     
#
# Parameters:
#     $vm  : The XML object representing the VM
#
# Return:
#
########################################################################
function DoStartPS1Test([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartPS1Test received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoStartPS1Test($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartPS1Test received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoStartPS1Test received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $vmName = $vm.vmName
    $hvServer = $vm.hvServer
    
    $currentTest = $vm.currentTest
    $testData = GetTestData $currentTest $xmlData
    $testScript = $testData.testScript
    
    $logFilename = "${TestDir}\${vmName}_${currentTest}_ps.log"

    $vm.testCaseResults = "False"
    
    if (! (test-path $testScript))
    {
        $msg = "Error: $vmName PowerShell test script does not exist: $testScript"
        LogMsg 0 $msg
        $msg | out-file $logFilename
        
        UpdateState $vm $PS1TestCompleted
    }
    else
    {
        #
        # Build a semicolon separated string of testParams
        #
        $params = CreateTestParamString $vm $xmlData
        $params += "scriptMode=TestCase;"
        $params += "ipv4=$($vm.ipv4);sshKey=$($vm.sshKey);"

        #
        # Start the PowerShell test case script
        #
        LogMsg 3 "Info : $vmName Run PowerShell test case script $testScript"
        
        $job = Start-Job -filepath $testScript -argumentList $vmName, $hvServer, $params
        if ($job)
        {
            $vm.jobID = [string] $job.id
            UpdateState $vm $PS1TestRunning
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) - Cannot start PowerShell job for test $currentTest"
            UpdateState $vm $PS1TestCompleted
        }
    }
}


########################################################################
#
# DoPS1TestRunning()
#
########################################################################
function DoPS1TestRunning ([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPS1TestRunning received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoPS1TestRunning($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPS1TestRunning received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoPS1TestRunning received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = GetTestTimeout $vm $xmlData
    if ($vm.timeouts.ps1TestRunningTimeout)
    {
        $timeout = $vm.timeouts.ps1TestRunningTimeout
    }
   
    $tooLong = HasItBeenTooLong $vm.stateTimestamp $timeout
    if ($tooLong)
    {
        AbortCurrentTest $vm "test $($vm.currentTest) timed out."
        return
    }

    $jobID = $vm.jobID
    $jobStatus = Get-Job -id $jobID
    if ($jobStatus -eq $null)
    {
        # We lost our job.  Fail the test and stop tests
        $vm.currentTest = "done"
        AbortCurrentTest $vm "Invalid jobId for test $($vm.currentTest)"
        return
    }
    
    if ($jobStatus.State -eq "Completed")
    {
        $vm.testCaseResults = "True"
        UpdateState $vm $PS1TestCompleted
    }
}


########################################################################
#
# DoPS1TestCompleted()
#
########################################################################
function DoPS1TestCompleted ([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPS1TestCompleted received an invalid vm parameter"
        return
    }

    LogMsg 9 "Info : DoPS1TestCompleted($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPS1TestCompleted received a null or invalid xmlData parameter - disabling VM"
        $vm.emailSummary += "DoPS1TestCompleted received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $vmName = $vm.vmName
    $currentTest = $vm.currentTest
    $logFilename = "${TestDir}\${vmName}_${currentTest}_ps.log"
    $summaryLog  = "${vmName}_summary.log"

    #
    # Collect log data
    #
    $completionCode = "Failed"
    $jobID = $vm.jobID
    if ($jobID -ne "none")
    {
        $jobResults = @(Receive-Job -id $jobID)
        if ($jobResults)
        {
            foreach ($line in $jobResults)
            {
                $line >> $logFilename
            }
            
            #
            # The last object in the $jobResults array will be the boolean
            # value the script returns on exit.  See if it is true.
            #
            #if ($jobResults[ $jobResults.Length - 1 ] -eq $True)
            if ($jobResults[-1] -eq $True)
            {
                $completionCode = "Success"
            }
        }
    }
    
    #
    # Update e-mail summary
    #
    #$vm.emailSummary += "    Test $($vm.currentTest)   : $completionCode.<br />"
    $vm.emailSummary += ("    Test {0,-25} : {1}<br />" -f $($vm.currentTest), $completionCode)
    if (test-path $summaryLog)
    {
        $content = Get-Content -path $summaryLog
        foreach ($line in $content)
        {
            $vm.emailSummary += "          $line<br />"
        }
        del $summaryLog
    }

    UpdateState $vm $DetermineReboot
}
