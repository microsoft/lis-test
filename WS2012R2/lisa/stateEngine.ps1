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
    Functions that make up the Lisa state engine.

.Description
    This PowerShell script implements the state engine which
    moves test VMs through the various states required to perform
    a test on a Linux VM.  Not all states are visited by each
    VM.  The test case definition will result in some states
    being skipped.

    A fairly complete list of states a VM might progress through
    would include the following.  The below descriptions are not
    complete.  The intent is to give the reader an understanding
    of what is done in each state and the possible state transitions.

      SystemDown
        - Make sure the VM is stopped.
        - Update the current test.
        - If no more tests set currentState to Finished
        - If test case has a setup script
            set currentState to RunSetupScript
        - else
            set currentState to StartSystem

      RunSetupScript
        - Run the setup secript (to reconfigure the VM)
        - Set currentState to StartSystem

      StartSystem
        - Start the VM
        - Make sure the VM transitions to state Running
        - Set currentState to SystemStarting

      SystemStarting
        - Get the VMs IP address
        - Test port 22 (the SSH port) with a 5 second timeout
        - If VM is listening on port 22
            set currentState to SystemUp

      SlowSystemStarting
        Enter this state only if SystemStarting state timed out.
        - Continue testing port 22

      DiagnoseHungSystem
        Enter this state only if SlowSystemStarting state timed out.
       - Log error that tests will not be performed on this VM.
        - Set currentTest to done
        - Set currentState to ForceShutdown

      SystemUp
        - Send a simple command to the VM via SSH and accept any prompts for server key
        - Set currentState to PushTestFiles

      PushTestFiles
        - Create a constants.sh file and populate with all test parameters
        - Push the constants.sh file to VM using SSH
        - Tell the VM to run dos2unix on the constants.sh file
        - Push the test script to the VM
        - Tell the VM to run dos2unix on the test script file
        - Tell the VM to chmod 755 testScript
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
        - write the command to a file named runtest.sh
        - copy runtest.sh file to VM
        - Tell VM to chmod 755 runtest.sh
        - Tell VM to run dos2unix on runtest.sh
        - Tell VM to start atd daemon
        - send command "at -f runtest.sh now" to VM
            This runs test script with both STDOUT and STDERR logged
            and allows the SSH connection to be closed.  This is needed
            so this script can process other VMs in parallel
        - set currentState to TestStarting

      TestStarting
        - test if the file ~/state.txt was created on the VM
        - if state.txt exists
            set currentState to TestRunning

      TestRunning
        - Copy ~/state.txt from VM using SSH
        - if contents of state.txt is not "TestRunning"
            set currentState to CollectLogFiles

      CollectLogFiles
        - Use state.txt to mark status of test case to completed, aborted, failed
        - Copy log file from VM and save in Lisa test directory
          Note: The saved logfile will be named:  <vmName>_<testCaseName>.log
                This is required since the test run may have multiple VMs and
                each VM may run the same test cases.
        - Delete state.txt on the VM
        - If test case has a posttest script
            Set currentState to RunPostTestScript
          else
            Set currentState to DetermineReboot

      RunPostTestScript
        - Verify test case lists a posttest script
        - Run the PowerShell posttest script in a separate PowerShell context
        - Set currentState to DetermineReboot

      DetermineReboot
        - Determine if we need to reboot the VM before the next test
        - if reboot required
            Set currentState to ShutdownSystem
          else
            Update currentTest
            Set currentState to SystemUp

      ShutdownSystem
        - Ask the VM to shutdown
        - Set currentState to ShuttingDown

      ShuttingDown
        - If timeout in this state
            Set currentState to ForceShutdown
        - If VM in Off state
            If currentTest has a CleanupScript
              Set currentState to RunCleanupScript
            else
              Set currentState to SystemDown

      ForceShutDown
        - If VM in Off state
            If currentTest has a CleanupScript
              Set currentState to RunCleanupScript
            else
              Set currentState to SystemDown
          else
            Stop the VM
        - If we timeout in this state
            Log the error
            Mark the VM as disabled (set state to Disabled)

      RunCleanUpScript
        - Run the cleanup secript (to undo configuration changes)
        - Set currentState to SystemDown

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
# States a VM can be in
#
New-Variable SystemDown          -value "SystemDown"          -option ReadOnly
New-Variable ApplyCheckpoint     -value "ApplyCheckpoint"     -option ReadOnly
New-variable RunSetupScript      -value "RunSetupScript"      -option ReadOnly
New-Variable StartSystem         -value "StartSystem"         -option ReadOnly
New-Variable SystemStarting      -value "SystemStarting"      -option ReadOnly
New-Variable SlowSystemStarting  -value "SlowSystemStarting"  -option ReadOnly
New-Variable DiagnoseHungSystem  -value "DiagnoseHungSystem"  -option ReadOnly
New-Variable SystemUp            -value "SystemUp"            -option ReadOnly
New-Variable WaitForDependencyVM -value "WaitForDependencyVM" -option ReadOnly
New-Variable PushTestFiles       -value "PushTestFiles"       -option ReadOnly
New-Variable RunPreTestScript    -value "RunPreTestScript"    -option ReadOnly
New-Variable StartTest           -value "StartTest"           -option ReadOnly
New-Variable TestStarting        -value "TestStarting"        -option ReadOnly
New-Variable TestRunning         -value "TestRunning"         -option ReadOnly
New-Variable CollectLogFiles     -value "CollectLogFiles"     -option ReadOnly
New-Variable RunPostTestScript   -value "RunPostTestScript"   -option ReadOnly
New-Variable DetermineReboot     -value "DetermineReboot"     -option ReadOnly
New-Variable ShutdownSystem      -value "ShutdownSystem"      -option ReadOnly
New-Variable ShuttingDown        -value "ShuttingDown"        -option ReadOnly
New-Variable ForceShutDown       -value "ForceShutDown"       -option ReadOnly
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
New-Variable TestSkipped         -value "TestSkipped"         -option ReadOnly

#
# test result codes
#
New-Variable Passed              -value "Passed"              -option ReadOnly
New-Variable Skipped             -value "Skipped"             -option ReadOnly
New-Variable Aborted             -value "Aborted"             -option ReadOnly
New-Variable Failed              -value "Failed"              -option ReadOnly

#
# Supported OSs
#
New-Variable LinuxOS             -value "Linux"               -option ReadOnly
New-Variable FreeBSDOS           -value "FreeBSD"             -option ReadOnly

#
# Generate JUnit formated XML object to store case results.
#
$testResult = GetJUnitXML

########################################################################
#
# RunICTests()
#
########################################################################
function RunICTests([XML] $xmlConfig, [string] $collect, [string] $noshutdown)
{
    <#
    .Synopsis
        Start tests running on the test VMs.
    .Description
        Reset all VMs to a known state of stopped.
        Add any additional any missing "required" XML elements to each
        vm definition.  Initialize the e-mail message that may be sent
        on test completion.
    .Parameter xmlConfig
        XML document driving the test.
    .Parameter noshutdown
        Flag to leave the VM running regardless of a testcase status.
    .Example
        RunICTests $xmlData
    #>

    if (-not $xmlConfig -or $xmlConfig -isnot [XML])
    {
        LogMsg 0 "Error: RunICTests received a bad xmlConfig parameter - terminating LISA"
        return
    }

    if (-not $collect -or $collect -isnot [string])
    {
        LogMsg 0 "Error: RunICTests received a bad collect parameter - terminating LISA"
        return
    }

    if (-not $noshutdown -or $noshutdown -isnot [string])
    {
        LogMsg 0 "Error: RunICTests received a bad noshutdown parameter: ${noshutdown} - terminating LISA"
        return
    }

    LogMsg 9 "Info : RunICTests($($vm.vmName))"

    #
    # Verify the Putty utilities exist.  Without them, we cannot talk to the Linux VM.
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
    # Reset each VM to a known state
    #
    foreach ($vm in $xmlConfig.config.VMs.vm)
    {
        LogMsg 5 "Info : RunICTests() processing VM $($vm.vmName)"
        $isSUTVM = $false
        if ($vm.role -eq $null)
        {
            $isSUTVM = $true

            $newElement = $xmlConfig.CreateElement("role")
            $newElement.set_InnerText("SUT")
            $results = $vm.AppendChild($newElement)
        }
        elseif ($vm.role.ToLower().StartsWith("nonsut"))
        {
            $isSUTVM = $false
        }
        elseif ($vm.role.ToLower().StartsWith("sut"))
        {
            $isSUTVM = $true
        }
        else
        {
            LogMsg 0 "Error: Unknown VM role specified in the XML file: $($vm.role)"
            return
        }

        #
        # Add the state related xml elements to each VM xml node
        #
        $xmlElementsToAdd = @("currentTest", "stateTimeStamp", "caseStartTime", "state", "emailSummary", "jobID", "testCaseResults", "iteration", "isRebooted")
        foreach($element in $xmlElementsToAdd)
        {
            if (-not $vm.${element})
            {
                $newElement = $xmlConfig.CreateElement($element)
                $newElement.set_InnerText("none")
                $results = $vm.AppendChild($newElement)
            }
        }

        $newElement = $xmlConfig.CreateElement("individualResults")
        $newElement.set_InnerText("");
        $vm.AppendChild($newElement);

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
        $vm.emailSummary += " build $($OSInfo.BuildNumber)<br />"
        $vm.emailSummary += "<br /><br />"

        if ($isSUTVM)
        {
            # Add test suite and test date time into test result XML
            #
            SetTimeStamp $testStartTime.toString()
            SetResultSuite $vm.suite
            #
            # Add Hyper-V host version into result XML
            #
            SetHypervVersion "$($OSInfo.Version)"
        }

        #
        #
        # Make sure the VM actually exists on the specific HyperV server
        #
        if ($null -eq (Get-VM $vm.vmName -ComputerName $vm.hvServer -ErrorAction SilentlyContinue))
        {
            LogMsg 0 "Warn : The VM $($vm.vmName) does not exist on server $($vm.hvServer)"
            if ($vm.role.ToLower().StartsWith("sut"))
            {
                LogMsg 0 "Warn : Tests will not be run on $($vm.vmName)"
                UpdateState $vm $Disabled

                $vm.emailSummary += "    The virtual machine $($vm.vmName) does not exist.<br />"
                $vm.emailSummary += "    No tests were run on $($vm.vmName)<br />"
                continue
            }
            else
            {
                LogMsg 0 "Error : the dependency VM $($vm.vmName) is missing. Testing will be ended."

                $vm.emailSummary += "    The virtual machine $($vm.vmName) does not exist.<br />"
                $vm.emailSummary += "    Testing is ended as the dependency VM is missing: $($vm.vmName)<br />"
                return
            }
        }
        else
        {
            LogMsg 10 "Info : Resetting vm $($vm.vmName)"
            ResetVM $vm $xmlConfig
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
            $vm.emailSummary += "    The VM could not be stopped.  It has been disabled.<br />"
            $vm.emailSummary += "   No tests were run on this VM`<br />"
            UpdateState $vm $Disabled
        }
    }

    $Script:LIS_version = $null

    #
    # run the state engine
    #
    DoStateMachine $xmlConfig $collect $noshutdown

    #
    # Add LIS version to the email summary text
    #
    if ([string]::IsNullOrWhiteSpace($Script:LIS_version)) {
        $vm.emailSummary += "<br />"
        $vm.emailSummary += "LIS Version :  Could not determine LIS version $Script:LIS_version"
    }
    else {
        $vm.emailSummary += "<br />"
        $vm.emailSummary += "LIS Version :  $Script:LIS_version"
    }
    $vm.emailSummary += "<br /><br />"
}


########################################################################
#
# ResetVM()
#
########################################################################
function ResetVM([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Make sure the test VM is stopped
    .Description
        Stop the test VM and then reset it to a snapshot.
        This ensures the VM starts the test run in a
        known good state.
    .Parameter vm
        XML element representing the test VM
    .Example
        ResetVM $vm
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: ResetVM was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : ResetVM( $($vm.vmName) )"

    #
    # Stop the VM.  If the VM is in a state other than running,
    # try to stop it.
    #
    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
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
    if ($v.State -ne "Off")
    {
        LogMsg 3 "Info : $($vm.vmName) is not in a stopped state - stopping VM"
        Stop-VM $vm.vmName -ComputerName $vm.hvServer -force | out-null

        $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
        if ($v.State -ne "Off")
        {
            LogMsg 0 "Error: ResetVM is unable to stop VM $($vm.vmName). VM has been disabled"
            $vm.emailSummary += "Unable to stop VM.  VM was disabled and no tests run<br />"
            UpdateState $vm $Disabled
            return
        }
    }

    #
    # Reset the VM to a snapshot to put the VM in a known state.  The default name is
    # ICABase.  This can be overridden by the global.defaultSnapshot in the global section
    # and then by the vmSnapshotName in the VM definition.
    #
    $snapshotName = "ICABase"

    if ($xmlData.config.global.defaultSnapshot)
    {
        $snapshotName = $xmlData.config.global.defaultSnapshot
        LogMsg 5 "Info : $($vm.vmName) Over-riding default snapshotName from global section to $snapshotName"
    }

    if ($vm.vmSnapshotName)
    {
        $snapshotName = $vm.vmSnapshotName
        LogMsg 5 "Info : $($vm.vmName) Over-riding default snapshotName from VM section to $snapshotName"
    }

    #
    # Find the snapshot we need and apply the snapshot
    #
    $snapshotFound = $false
    $snaps = Get-VMSnapshot $vm.vmName -ComputerName $vm.hvServer
    foreach($s in $snaps)
    {
        if ($s.Name -eq $snapshotName)
        {
            LogMsg 3 "Info : $($vm.vmName) is being reset to snapshot $($s.Name)"
            Restore-VMSnapshot $s -Confirm:$false | out-null
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
        $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
        if ($v.State -eq "Paused")
        {
            LogMsg 3 "Info : $($vm.vmName) - resetting to a stopped state after restoring a snapshot"
            Stop-VM $vm.vmName -ComputerName $vm.hvServer -Force | out-null
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
########################################################################
function DoStateMachine([XML] $xmlConfig, [string] $collect, [string] $noshutdown)
{
    <#
    .Synopsis
        Main function of the state machine.
    .Description
        Move each VM through the various states required
        to run a test on a VM.
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
        foreach( $vm in $xmlConfig.config.VMs.vm )
        {
            switch($vm.state)
            {
            $SystemDown
                {
                    DoSystemDown $vm $xmlConfig
                    $done = $false
                }

            $ApplyCheckpoint
                {
                    DoApplyCheckpoint $vm $xmlConfig
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
                    DoDiagnoseHungSystem $vm $xmlConfig $noshutdown
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

            $WaitForDependencyVM
                {
                    DoWaitForDependencyVM $vm $xmlConfig
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
                    DoCollectLogFiles $vm $xmlConfig $collect
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
                    DoShutdownSystem $vm $xmlConfig $noshutdown
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
                    DoFinished $vm $xmlConfig
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
########################################################################
function DoSystemDown([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Ensure the VM is stopped and update some VM attributes.
    .Description
        Update the VMs currentTest.  Transition to RunSetupScript if the currentTest
        defines a setup script.  Otherwise, transition to StartSystem
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoSystemDown $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemDown received an bad VM parameter"
        return
    }

    LogMsg 9 "Info : Entering DoSystemDown( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemDown received a null or bad xmlData parameter - VM $($vm.vmName) disabled"
        $vm.emailSummary += "    DoSystemDown received a null xmlData parameter - VM disabled<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    #
    # Make sure the VM is stopped
    #
    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
    if ($v.State -ne "Off")
    {
        LogMsg 0 "Error: $($vm.vmName) entered SystemDown in a non-stopped state`n       The VM will be disabled"
        $vm.emailSummary += "          SystemDown found the VM in a non-stopped state - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
        return
    }

    if ($vm.role.ToLower().StartsWith("sut"))
    {
        #for SUT VMs:

        #
        # Update the VMs current test
        #
        UpdateCurrentTest $vm $xmlData

        #
        # Mark current test the first case or after rebooted
        #
        $vm.isRebooted = $true.ToString()

        $iterationMsg = $null
        if ($vm.iteration -ne "-1")
        {
            $iterationMsg = " (iteration $($vm.iteration))"
        }
        LogMsg 0 "Info : $($vm.vmName) currentTest updated to $($vm.currentTest) ${iterationMsg}"

        $vm.caseStartTime = [DateTime]::Now.ToString()

        if ($($vm.currentTest) -eq "done")
        {
            UpdateState $vm $Finished

            #check: if all SUT VMs are set to Finished, then shutdwon the NonSUT VM
            $allSUTVMDone = $true

            foreach( $v in $xmlData.config.VMs.vm )
            {
                if ($vm.role.ToLower().StartsWith("sut"))
                {
                    if ($($v.state) -ne $Finished)
                    {
                        $allSUTVMDone = $false
                    }
                }
            }

            #for NonSUT VM, if all SUT VMs are done, then shutdown them
            if ($allSUTVMDone -eq $true)
            {
                foreach( $v in $xmlData.config.VMs.vm )
                {
                    if ($vm.role.ToLower().StartsWith("nonsut"))
                    {
                        if ($($v.state) -eq $Finished)
                        {
                            ShutDownVM $v
                        }
                    }
                }
            }
        }
        else
        {
            UpdateState $vm $ApplyCheckpoint
        }
    }
    else
    {
        #for NON-SUT VMs, put the VM state to run preStartScript or StartSystem
        if ($vm.preStartConfig)
        {
            UpdateState $vm $RunSetupScript
        }
        else
        {
            UpdateState $vm $StartSystem
        }
    }
}


########################################################################
#
# DoApplyCheckpoint()
#
########################################################################
function DoApplyCheckpoint([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Apply checkpoint to let VM go into a know status
        if RevertDefaultSnapshot=True.
    .Description
        Apply checkpoint if RevertDefaultSnapshot=True. Then transition
        to RunSetupScript if the currentTest defines a setup script.
        Otherwise, transition to StartSystem. If RevertDefaultSnapshot=False
        or not configured, there's no checkpoint restoring applied in VM
        and do state transition instead.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter xmlData
        XML document for the test.
    .Example
        DoSystemDown $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoApplyCheckpoint received an bad VM parameter"
        return
    }

    LogMsg 9 "Info : Entering DoApplyCheckpoint( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoApplyCheckpoint received a null or bad xmlData parameter - VM $($vm.vmName) disabled"
        $vm.emailSummary += "    DoApplyCheckpoint received a null xmlData parameter - VM disabled<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    $testData = GetTestData $vm.currentTest $xmlData
    if ($testData -is [System.Xml.XmlElement])
    {
        # Do not need to recover from RevertDefaultSnapshot
        if (-not $testData.RevertDefaultSnapshot -or $testData.RevertDefaultSnapshot -eq "False")
        {
            LogMsg 9 "Info : noCheckpoint is not configured or set to True."
            if (-not (VerifyTestResourcesExist $vm $testData))
            {
                #
                # One or more resources used by the VM or test case does not exist - fail the test
                #
                $testName = $testData.testName
                $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, $Failed)
                $vm.emailSummary += "          Missing resources<br />"
                $vm.currentTest = "done"
                UpdateState $vm $Disabled
            }
        }
        # Case requires a fresh new state VM to run.
        else
        {
            #
            # Reset the VM to a snapshot to put the VM in a known state.  The default name is
            # ICABase.  This can be overridden by the global.defaultSnapshot in the global section
            # and then by the vmSnapshotName in the VM definition.
            #
            $snapshotName = "ICABase"

            if ($xmlData.config.global.defaultSnapshot)
            {
                $snapshotName = $xmlData.config.global.defaultSnapshot
                LogMsg 5 "Info : $($vm.vmName) Over-riding default snapshotName from global section to $snapshotName"
            }

            if ($vm.vmSnapshotName)
            {
                $snapshotName = $vm.vmSnapshotName
                LogMsg 5 "Info : $($vm.vmName) Over-riding default snapshotName from VM section to $snapshotName"
            }

            #
            # Find the snapshot we need and apply the snapshot
            #
            $snapshotFound = $false
            $snaps = Get-VMSnapshot $vm.vmName -ComputerName $vm.hvServer
            foreach($s in $snaps)
            {
                if ($s.Name -eq $snapshotName)
                {
                    LogMsg 3 "Info : $($vm.vmName) is being reset to snapshot $($s.Name)"
                    Restore-VMSnapshot $s -Confirm:$false | out-null
                    $snapshotFound = $true
                    break
                }
            }

            #
            # Make sure the snapshot left the VM in a stopped state.
            #
            if ($snapshotFound)
            {
                #
                # If a VM is in the Suspended (Saved) state after applying the snapshot,
                # the following will handle this case
                #
                $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
                if ($v.State -eq "Paused")
                {
                    LogMsg 3 "Info : $($vm.vmName) - resetting to a stopped state after restoring a snapshot"
                    Stop-VM $vm.vmName -ComputerName $vm.hvServer -Force | out-null
                }
            }
            else
            {
                LogMsg 0 "Warn : $($vm.vmName) does not have a snapshot named $snapshotName."
            }
        }
    }
    else
    {
        LogMsg 0 "Error: No test data for test $($vm.currentTest) in the .xml file`n       $($vm.vmName) has been disabled"
        $vm.emailSummary += "          No test data found for test $($vm.currentTest)<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    if ($vm.preStartConfig -or $testData.setupScript)
    {
        UpdateState $vm $RunSetupScript
    }
    else
    {
        UpdateState $vm $StartSystem
    }
}


########################################################################
#
# DoRunSetupScript()
#
########################################################################
function DoRunSetupScript([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Run a setup script to reconfigure a VM.
    .Description
        If the currentTest has a setup script defined, run the
        setup script to reconfigure the VM.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoRunSetupScript $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunSetupScript() was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : DoRunSetupScript( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunSetupScript received a null or bad xmlData parameter - terminating VM"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    #run preStartScript if has
    if ($vm.preStartConfig)
    {
        if ($vm.preStartConfig.File)
        {
            foreach ($preStartScript in $vm.preStartConfig.file)
            {
                LogMsg 3 "Info : $($vm.vmName) running preStartConfig script '${preStartScript}' "
                $sts = RunPSScript $vm $preStartScript $xmlData "preStartConfig"
                if (-not $sts)
                {
                LogMsg 0 "Error: VM $($vm.vmName) preStartConfig script: $preStartScript failed"
                }
            }
        }
        else  # original syntax of <preStartConfig>.\setupscripts\Config-VM.ps1</preStartConfig>
        {
            LogMsg 3 "Info : $($vm.vmName) - starting preStart script $($vm.preStartConfig)"
            $sts = RunPSScript $vm $($vm.preStartConfig) $xmlData "preStartConfig"
            if (-not $sts)
            {
                LogMsg 0 "Error: VM $($vm.vmName) preStartConfig script: $($vm.preStartConfig) failed"
            }
        }
    }

    if ($vm.role.ToLower().StartsWith("sut"))
    {
        #
        # for SUT VMs:
        # Run setup script if one is specified (this setup Script is defined in testcase level)
        #
        $testData = GetTestData $($vm.currentTest) $xmlData
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
                            $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Aborted - setup script failed")
                            #$vm.emailSummary += ("    Test {0,-25} : {2}<br />" -f $($vm.currentTest), $iterationMsg, $completionCode)
                            SetTestResult $vm.currentTest $Aborted $xmlData
                            SetRunningTime $vm.currentTest $vm
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
                        $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Aborted - setup script failed")
                        SetTestResult $vm.currentTest $Aborted $xmlData
                        SetRunningTime $vm.currentTest $vm

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
            LogMsg 0 "Error: $($vm.vmName) could not find test data for $($vm.currentTest)`n       The VM $($vm.vmName) will be disabled"
            $vm.emailSummary += "Test $($vm.currentTest) : Aborted (no test data)<br />"
            $vm.currentTest = "done"
            UpdateState $vm $Disabled
        }
    }
    #for Non-SUT VMs:
    # NonSUT will not run test cases directly so there will not have setup script defined
    else
    {
        UpdateState $vm $StartSystem
    }
}

########################################################################
#
# DoStartSystem()
#
########################################################################
function DoStartSystem([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Start the VM.
    .Description
        Start the VM and verify it transitions to a Hyper-V Running state.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test
    .Example
        DoStartSystem $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartSystem received an bad VM object"
        return
    }

    LogMsg 9 "Info : DoStartSystem( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartSystem received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "    DoStartSystem received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $Disabled
    }

    #
    # Make sure the VM is in the stopped state
    #
    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
    $hvState = $v.State
    if ($hvState -ne "Off")
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
    Start-VM $vm.vmName -ComputerName $vm.hvServer | out-null

    $timeout = 180
    while ($timeout -gt 0)
    {
        #
        # Check if the VM is in the Hyper-v Running state
        #
        $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
        if ($($v.State) -eq "Running")
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

        $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
        Stop-VM $v -ComputerName $vm.hvServer | out-null
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
########################################################################
function DoSystemStarting([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Check if OS on VM is up.
    .Description
        Check if the VM is listening on port 22 (sshd).
        Once Sshd is accessable, we can send work to the VM.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoSystemStarting $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemStarting received an bad VM object"
        return
    }

    LogMsg 9 "Info : Entering DoSystemStarting( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemStarting was passed a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoSystemStarting received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
    if ($v.State -ne "Running")
    {
        LogMsg 0 "Error: $($vm.vmName) SystemStarting entered state without being in a HyperV Running state - disabling VM"
        $vm.emailSummary += "    SystemStarting entered without being in a HyperV Running state - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = 300

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
        # If an IP address was not provided in the .XML file, try to
        # determine the VMs IP address
        #
        #if (-not $vm.ipv4)
        #{
        #    $ipv4 = GetIPv4 $vm.vmName $vm.hvServer
        #    if ($ipv4)
        #    {
        #        #
        #        # Update the VMs copy of the IPv4 address
        #        #
        #        $vm.ipv4 = [String] $ipv4
        #    }
        #}

        $ipv4 = $null
        LogMsg 9 "Debug: vm.ipv4 = $($vm.ipv4)"

        #
        # Need to ask the VM for the IP address on every
        # test.  But we also want to honor a <ipv4> value
        # if it was specified.
        #
        if (-not $vm.ipv4)
        {
            LogMsg 9 "Debug: vm.ipv4 is NULL"
            $ipv4 = GetIPv4 $vm.vmName $vm.hvServer
            if ($ipv4)
            {
                # Update the VMs copy of the IPv4 address
                $vm.ipv4 = [String] $ipv4
                LogMsg 9 "Debug: Setting VMs IP address to $($vm.ipv4)"
            }
            else
            {
                return
            }
        }

        #
        # Update the vm.ipv4 value if the VMs IP address changed
        #
        $ipv4 = GetIPv4 $vm.vmName $vm.hvServer
        LogMsg 9 "Debug: vm.ipv4 = $($vm.ipv4) and ipv4 = ${ipv4} "
        if ($ipv4 -and ($vm.ipv4 -ne [String] $ipv4))
        {
            LogMsg 9 "Updating VM IP from $($vm.ipv4) to ${ipv4}"
            $vm.ipv4 = [String] $ipv4
        }

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
########################################################################
function DoSlowSystemStarting([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Monitor a system that is taking longer than average to start.
    .Description
        Continue monitoring port 22 for the VM
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoSlowSystemStarting $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSlowSystemStarting received an bad vm object"
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

    $timeout = 180
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
        LogMsg 9 "=================The  VMs IP address to $($vm.ipv4)======================"
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
########################################################################
function DoDiagnoseHungSystem([System.Xml.XmlElement] $vm, [XML] $xmlData, [String] $noshutdown)
{
    <#
    .Synopsis
        System has taken too long to start.
    .Description
        This state is only reached if the system too long to start.
        Current implementation of this state is to log an error, set
        the current test to "Done", and let the state engine stop the VM.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoDiagnoseHungSystem $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoDiagnoseHungSystem received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : Entering DoDiagnoseHungSystem()"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoDiagnoseHungSystem was passed a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoDiagnoseHungSystem received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # Current behavior for this function is defined to just log some messages
    # and then try to stop the VM
    #
    LogMsg 0 "Warn : $($vm.vmName) never booted for test $($vm.currentTest) on first try"

    # Take a Console Screenshot
    if (($testDir.Contains("\\")) -or ($testDir.Contains(":\")))
    {
        $BMPName = "${testDir}\$($vm.currentTest)_ConsoleScreenShot.bmp"
    }
    else
    {
        $BMPName = (pwd).Path + "\" + "${testDir}\$($vm.currentTest)_ConsoleScreenShot.bmp"
    }

    $VMName = $vm.vmName
    Add-Type -AssemblyName "System.Drawing"
    $VMCS = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter "ElementName='$($VMName)'"

    # This is the default resolution in most cases
    [int]$xResolution = 1152
    [int]$yResolution = 864
    LogMsg 0 "Info: Screenshot was captured on this location $BMPName "

    try
    {
        # This will capture a screenshot at the default resolution of 1152*864
        (TakeConsoleScreenShot $VMCS $xResolution $yResolution).Save($BMPName)
    }
    catch
    {
        # Sometimes 1152*864 resolution is not available on VM Console
        # In this case a screenshot with 640*480 resolution will be taken
        [int]$xResolution = 640
        [int]$yResolution = 480
        (TakeConsoleScreenShot $VMCS $xResolution $yResolution).Save($BMPName)
    }

    $currentTest = GetTestData $($vm.currentTest) $xmlData
    if ($noshutdown -eq "True") {
        $testName = $($vm.currentTest)
        $testData = GetTestData $testName $xmlData
        $completionCode = $Aborted
        LogMsg 0 "Info : NoShutdown parameter is True. Skipping DoDiagnoseHungSystem($($vm.vmName))"
        LogMsg 0 "Error: $($vm.vmName) did not boot for test $testName "
        LogMsg 0 "Info : $($vm.vmName) Status for test $testName  = ${completionCode}"
        if ($testData.OnError -eq "Abort") {
            LogMsg 0 "Warn : Test is set to abort on error. Exiting"
            $vm.currentTest = "done"
        }
        SetTestResult $currentTest $completionCode $xmlData
        UpdateState $vm $Finished
     }
    else {
        #
        # Proceed with restarting the VM
        #
        Start-Sleep -s 5
        $timeout = 60
        Stop-VM -Name $vm.vmName -ComputerName $vm.hvServer -Force -TurnOff
        while ($timeout -gt 0)
        {
            $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
            if ( $($v.State) -eq "Off" )
            {
                LogMsg 0 "Warn : $($vm.vmName) is now starting for the second time for test $($vm.currentTest)"
                Start-VM $vm.vmName -ComputerName $vm.hvServer | out-null
                $timeout_startVM = 60
                while ($timeout_startVM -gt 0)
                {
                    #
                    # Check if the VM is in the Hyper-v Running state
                    #
                    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
                    if ($($v.State) -eq "Running")
                    {
                        break
                    }

                    Start-Sleep -s 1
                    $timeout_startVM -= 1
                }

                $ipv4 = $null
                $hasBooted = $false
                [int]$timeoutBoot = 25
                # Update the vm.ipv4 value if the VMs IP address changed
                while (($hasBooted -eq $false) -and ($timeoutBoot -ge 0))
                {
                    Start-Sleep -s 1
                    $ipv4 = GetIPv4 $vm.vmName $vm.hvServer
                    LogMsg 9 "Debug: vm.ipv4 = $($vm.ipv4)"
                    if ($ipv4 -and ($vm.ipv4 -ne [String] $ipv4))
                    {
                        LogMsg 9 "Updating VM IP from $($vm.ipv4) to ${ipv4}"
                        $vm.ipv4 = [String] $ipv4
                    }
                    $sts = TestPort $vm.ipv4 -port 22 -timeout 5
                    if ($sts)
                    {
                        $hasBooted = $true
                    }
                    $timeoutBoot -= 1
                }

                if ($hasBooted -eq $true)
                {
                    UpdateState $vm $SystemUp
                }
                else
                {
                    $testName = $($vm.currentTest)
                    $testData = GetTestData $testName  $xmlData
                    $completionCode = $Aborted

                    LogMsg 0 "Error: $($vm.vmName) did not boot after second try for test $testName "
                    LogMsg 0 "Info : $($vm.vmName) Status for test $testName  = ${completionCode}"

                    if ($testData.OnError -eq "Abort") {
                        LogMsg 0 "Warn : Test is set to abort on error. Exiting"
                        $vm.currentTest = "done"
                        # UpdateState $vm $ForceShutdown
                        UpdateState $vm $Disabled
                    }
                    SetTestResult $currentTest $completionCode $xmlData
                    $vm.emailSummary += ("    Test {0,-25} : {1}<br />" -f $testName, $completionCode)
                    UpdateState $vm $ForceShutdown
                }
            }
            else
            {
                $timeout -= 1
                Start-Sleep -S 1
            }
        }
    }
}


########################################################################
#
# DoSystemUp()
#
########################################################################
function DoSystemUp([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Verify the system is up and accessible
    .Description
        Send a command to the VM and accept an SSH prompt for server
        key.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoSystemUp $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoSystemUp received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoSystemUp($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoSystemUp received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoSystemUp received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    if (-not [bool]$vm.isRebooted)
    {
         $vm.caseStartTime = [DateTime]::Now.ToString()
    }
    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

    #
    # The first time we SSH into a VM, SSH will prompt to accept the server key.
    # Send a "no-op command to the VM and assume this is the first SSH connection,
    # so pipe a 'y' respone into plink
    #
    LogMsg 9 "INFO : Call: echo y | bin\plink -i ssh\$sshKey root@$hostname exit"
    echo y | bin\plink -i ssh\${sshKey} root@${hostname} exit

    #
    #Determine LIS version on guest VM
    #
    if ($Script:LIS_version -eq $null) {
        $Script:LIS_version=.\bin\plink.exe -i ssh\${sshKey} root@${hostname} "modinfo hv_vmbus 2> /dev/null | grep -w 'version:' | cut -d : -f 2 | sed 's/^[ \t]*//;s/ //g'"
        if ([string]::IsNullOrWhiteSpace($Script:LIS_version)) {
            $Script:LIS_version=.\bin\plink.exe -i ssh\${sshKey} root@${hostname} "modinfo hv_vmbus 2> /dev/null | grep -w 'vermagic:' | cut -d : -f 2 | sed 's/^[ \t]*//;s/SMP mod_unload modversions//g;s/ //g'"
            if ([string]::IsNullOrWhiteSpace($Script:LIS_version)) {
                $Script:LIS_version=.\bin\plink.exe -i ssh\${sshKey} root@${hostname} "modinfo hv_netvsc 2> /dev/null | grep -w 'vermagic:' | cut -d : -f 2 | sed 's/^[ \t]*//;s/SMP mod_unload modversions//g;s/ //g'"
            }
        }
    }

    #
    # Determine the VMs OS
    #
    $os = [string](GetOSType $vm)
    LogMsg 9 "INFO : The OS type is $os"

    If ($vm.role.ToLower().StartsWith("sut"))
    {
        #
        # Add guest kernel version and firmware info int result XML
        #
        $kernelVer = GetKernelVersion
        $firmwareVer = GetFirmwareVersion
        SetOSInfo $kernelVer $firmwareVer

        #for SUT VM, needs to wait for NonSUT VM startup
        UpdateState $vm $WaitForDependencyVM
    }
    else
    {
         #for NonSUT VM, run postStartConfig now (map to SUT VM's RunPreTestScript State).
         UpdateState $vm $RunPreTestScript
    }

}

########################################################################
#
# DoPushTestFiles()
#
########################################################################
function DoPushTestFiles([System.Xml.XmlElement] $vm, [XML] $xmlData)
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
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoPushTestFiels $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPushTestFiles received an bad null vm parameter"
        return
    }

    LogMsg 9 "Info : DoPushTestFiles($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPushTestFiles received a null or bad xmlData parameter - disabling VM"
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
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
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
    # Add the ipv4 param that we're using to talk to the VM. This way, tests that deal with multiple NICs can avoid manipulating the one used here
    #
    if ($vm.ipv4)
    {
        LogMsg 9 "Info : $($vm.vmName) Adding ipv4=$($vm.ipv4)"
        "ipv4=$($vm.ipv4)" | out-file -encoding ASCII -append -filePath $constFile
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
            $vm.emailSummary += "    Cannot push $constFile to VM<br />"
            $vm.testCaseResults = $Aborted
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
                $vm.testCaseResults = $Aborted
                UpdateState $vm $DetermineReboot
                return
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) cannot create dos2unix command for ${constFile}"
            $vm.emailSummary += "    Unable to create dos2unix command for ${constFile}<br />"
            $vm.testCaseResults = $Aborted
            UpdateState $vm $DetermineReboot
            return
        }

        del $constFile -ErrorAction:SilentlyContinue
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
            LogMsg 5 "Info : $($vm.vmName) sending '${testFile}' to VM"
            if (-not (SendFileToVM $vm $testFile) )
            {
                LogMsg 0 "Error: $($vm.vmName) error pushing file '$testFile' to VM"
                $vm.emailSummary += "    Unable to push test file '$testFile' to VM<br />"
                $vm.testCaseResults = $Aborted
                UpdateState $vm $DetermineReboot
                return
            }
        }
    }


    $testScript = $($testData.testScript).Trim()
    if ($testScript -eq $null)
    {
        LogMsg 0 "Error: $($vm.vmName) test case $($vm.currentTest) does not have a testScript"
        $vm.emailSummary += "    Test case $($vm.currentTest) does not have a testScript.<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    #
    # If the test script is not a PowerShell script, do some additional
    # work - e.g. dos2unix, set x bit
    #
    if (-not ($testScript.EndsWith(".ps1")))
    {
        #
        # Make sure the test script has Unix EOL
        #
        LogMsg 3 "Info : $($vm.vmname) converting EOL for file $testScript"
        $dos2unixCmd = GetOSDos2UnixCmd $vm $testScript
        #$dos2unixCmd = "dos2unix -q $testScript"
        if ($dos2unixCmd)
        {
            if (-not (SendCommandToVM $vm "${dos2unixCmd}") )
            {
                LogMsg 0 "Error: $($vm.vmName) unable to set EOL on test script file $testScript"
                $vm.emailSummary += "    Unable to set EOL on file $testScript<br />"
                $vm.testCaseResults = $Aborted
                UpdateState $vm $DetermineReboot
                return
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) cannot create dos2unix command for ${testScript}"
            $vm.emailSummary += "    Unable to create dos2unix command for $testScript<br />"
            $vm.testCaseResults = $Aborted
            UpdateState $vm $DetermineReboot
            return
        }

        #
        # Set the X bit to allow the script to run
        #
        LogMsg 3 "Info : $($vm.vmName) setting x bit on $testScript"
        if (-not (SendCommandToVM $vm "chmod 755 $testScript") )
        {
            LogMsg 0 "$($vm.vmName) unable to set x bit on test script $testScript"
            $vm.emailSummary += "    Unable to set x bit on test script $testScript<br />"
            $vm.testCaseResults = $Aborted
            UpdateState $vm $DetermineReboot
            return
        }
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
    <#
    .Synopsis
        Run a pretest PowerShell script.
    .Description
        If the currentTest defines a PreTest script, run it
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoRunPreTestScript $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunPreTestScript() was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : DoRunPreTestScript( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunPreTestScript received a null or bad xmlData parameter - terminating VM"
    }
    else
    {
        If ($vm.role.ToLower().StartsWith("sut"))
        {
            #
            # For SUT VMs: Run pretest script if one is specified
            #
            $testData = GetTestData $($vm.currentTest) $xmlData
            $testName = $testData.testName
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
                            LogMsg 3 "Info : $($vm.vmName) running PreTest script '${script}' for test $($testData.testName)"
                            $sts = RunPSScript $vm $script $xmlData "PreTest"
                            if (! $sts)
                            {
                                LogMsg 0 "Error: $($vm.vmName) PreTest script ${script} for test $($testData.testName) failed"
                                $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Aborted - pretest script failed")

                                SetTestResult $vm.currentTest $Aborted $xmlData
                                SetRunningTime $vm.currentTest $vm

                                UpdateState $vm $DetermineReboot
                                return
                            }
                        }
                    }
                    else # Original syntax of <pretest>setupscripts\myPretest.ps1</pretest>
                    {
                        LogMsg 3 "Info : $($vm.vmName) - starting preTest script $($testData.setupScript)"

                        $sts = RunPSScript $vm $($testData.preTest) $xmlData "PreTest"
                        if (-not $sts)
                        {
                            LogMsg 0 "Error: VM $($vm.vmName) preTest script for test $($testData.testName) failed"
                            $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f ${testName}, "Aborted - pretest script failed")

                            SetTestResult $vm.currentTest $Aborted $xmlData
                            SetRunningTime $vm.currentTest $vm
                            UpdateState $vm $DetermineReboot
                            return
                        }
                    }
                }
                else
                {
                    LogMsg 9 "Info: $($vm.vmName) entered RunPreTestScript with no preTest script defined for test $($vm.currentTest)"
                }
            }
            else
            {
                LogMsg 0 "Error: $($vm.vmName) could not find test data for $($vm.currentTest)"
            }
            UpdateState $vm $StartTest
        }
        else
        {
            #
            # For NonSUT VMs: Run postStartConfig script defined in the XML file, VM section
            #
            if ($vm.postStartConfig)
            {
                $sts = RunPSScript $vm $($vm.postStartConfig) $xmlData "postStartConfig"
                if (-not $sts)
                {
                    LogMsg 0 "Error: Info: NonSUT VM $($vm.vmName) postStartConfig script for test $($vm.postStartConfig) failed"
                }
            }
            else
            {
                LogMsg 9 "Info : NonSUT VM: $($vm.vmName) entered RunPreTestScript with no postStartConfig script defined"
            }

            UpdateState $vm $Finished
        }
    }
}


########################################################################
#
# DoStartTest()
#
########################################################################
function DoStartTest([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Start the test running on the VM
    .Description
        Create the runtest.sh, push it to the VM, set the x bit on the
        runtest.sh, start ATD on the VM, and submit runtest.sh vi at.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoStartTest $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartTest received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoStartTest($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartTest received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoStartTest received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # Create a shell script to run the actual test script.
    # This is so the test script output can be directed into a specified log file.
    #
    del runtest.sh -ErrorAction "SilentlyContinue"

    #
    # Create the runtest.sh script, push it to the VM, set the x bit, then delete local copy
    #
    $testData = GetTestData $vm.currentTest $xmlData
    if (-not $testData)
    {
        LogMsg 0 "Error: $($vm.vmName) cannot fine test data for test '$($vm.currentTest)"
        $vm.emailSummary += "    Cannot fine test data for test '$($vm.currentTest)<br />"
        $vm.testCaseResults = $Aborted
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
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    if ($testScript.EndsWith(".ps1"))
    {
        UpdateState $vm $StartPS1Test
        return
    }

    #"./$($testData.testScript) &> $($vm.currentTest).log " | out-file -encoding ASCII -filepath runtest.sh
    $runCmd = GetOSRunTestCaseCmd $($vm.os) $($testData.testScript) "$($vm.currentTest).log"
    if (-not $runCmd)
    {
        LogMsg 0 "Error: $($vm.vmName) unable to create runtest.sh"
        $vm.emailSummary += "    Unable to create runtest.sh<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    $runCmd | out-file -encoding ASCII -filepath runtest.sh
    LogMsg 3 "Info : $($vm.vmName) pushing file runtest.sh"
    if (-not (SendFileToVM $vm "runtest.sh" "runtest.sh") )
    {
        LogMsg 0 "Error: $($vm.vmName) cannot copy runtest.sh to VM"
        $vm.emailSummary += "    Cannot copy runtest.sh to VM<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    del runtest.sh -ErrorAction:SilentlyContinue

    LogMsg 3 "Info : $($vm.vmName) setting the x bit on runtest.sh"
    if (-not (SendCommandToVM $vm "chmod 755 runtest.sh") )
    {
        LogMsg 0 "Error: $($vm.vmName) cannot set x bit on runtest.sh"
        $vm.emailSummary += "    Cannot set x bit on runtest.sh<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    $dos2unixCmd = GetOSDos2UnixCmd $vm "runtest.sh"
    #$dos2unixCmd = "dos2unix -q runtest.sh"
    if (-not $dos2unixCmd)
    {
        LogMsg 0 "Error: $($vm.vmName) cannot create dos2unix command for runtest.sh"
        $vm.emailSummary += "    Cannot create dos2unix command for runtest.sh<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    LogMsg 3 "Info : $($vm.vmName) correcting the EOL for runtest.sh"
    if (-not (SendCommandToVM $vm "${dos2unixCmd}") )
    {
        LogMsg 0 "Error: $($vm.vmName) Unable to correct the EOL on runtest.sh"
        $vm.emailSummary += "    Unable to correct the EOL on runtest.sh<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    #
    # Make sure atd daemon is running on the remote machine
    #
    LogMsg 3 "Info : $($vm.vmName) enabling atd daemon"
    #if (-not (SendCommandToVM $vm "/etc/init.d/atd start") )
    if (-not (StartOSAtDaemon $vm))
    {
        LogMsg 0 "Error: $($vm.vmName) Unable to start atd on VM"
        $vm.emailSummary += "    Unable to start atd on VM<br />"
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
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
        $vm.testCaseResults = $Aborted
        UpdateState $vm $DetermineReboot
        return
    }

    UpdateState $vm $TestStarting
}


########################################################################
#
# DoTestStarting()
#
########################################################################
function DoTestStarting([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Check to see if the test actually started
    .Description
        When a test script starts, it will create a file on the
        VM named ~/state.txt.  Use SSH to verify if this file
        exists.
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoTestStarting $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoTestStarting received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoTestStarting($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoTestStarting received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoTestStarting received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $timeout = 600
    if ($vm.timeouts.testStartingTimeout)
    {
        $timeout = $vm.timeouts.testStartingTimeout
    }

    if ( (HasItBeenTooLong $vm.stateTimestamp $timeout) )
    {
        LogMsg 0 "Error: $($vm.vmName) time out starting test $($vm.currentTest)"
        $vm.emailSummary += "    time out starting test $($vm.currentTest)<br />"
        $vm.testCaseResults = $Aborted
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
########################################################################
function DoTestRunning([System.Xml.XmlElement] $vm, [XML] $xmlData)
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
          TestSkipped    - The test is not supported by this scenario
          TestAborted   - An error occured while setting up the test
          TestFailed    - An error occured during the test

        Leave this state once the value is not TestRunning
    .Parameter vm
        XML Element representing the VM under test.
    .Parameter $xmlData
        XML document for the test.
    .Example
        DoTestRunning $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoTestRunning received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoTestRunning($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoTestRunning received a null or bad xmlData parameter - disabling VM"
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
        $vm.testCaseResults = $Aborted
        UpdateState $vm $CollectLogFiles
        return
    }

    $stateFile = "state.txt"

    del $stateFile -ErrorAction "SilentlyContinue"

    if ( (GetFileFromVM $vm $stateFile ".") )
    {
        if (test-path $stateFile)
        {
            $vm.testCaseResults = $Aborted
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                if ($contents -eq $TestRunning)
                {
                    return
                }
                elseif ($contents -eq $TestCompleted)
                {
                    $vm.testCaseResults = $Passed
                    UpdateState $vm $CollectLogFiles
                }
                elseif ($contents -eq $TestSkipped)
                {
                    $vm.testCaseResults = $Skipped
                    UpdateState $vm $CollectLogFiles
                }
                elseif ($contents -eq $TestAborted)
                {
                    AbortCurrentTest $vm "$($vm.vmName) Test $($vm.currentTest) aborted. See logfile for details"
                }
                elseif($contents -eq $TestFailed)
                {
                    AbortCurrentTest $vm "$($vm.vmName) Test $($vm.currentTest) failed. See logfile for details"
                    $vm.testCaseResults = $Failed
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
# GenerateGeneralLogFile()
#
########################################################################
function GenerateGeneralLogFile([System.Xml.XmlElement] $vm)
{
    <#
    .Synopsis
        Generate general info from the VM
    .Description
        Generate a set of general information about the VM
        and his functionality
    .Parameter vm
        XML element representing the test VM
    .Example
        GenerateGeneralLogFile $testVM
    #>

    SendCommandToVM $vm "echo '##### VM_NAME: $($vm.vmName) #####' >> generalinfo.log"
    SendCommandToVM $vm "echo '##### ComputerName: $($vm.hvServer) #####' >> generalinfo.log"
    SendCommandToVM $vm "echo '##### Kernel version #####' >> generalinfo.log"
    SendCommandToVM $vm "uname -r >> generalinfo.log"
    SendCommandToVM $vm "echo >> generalinfo.log && echo >> generalinfo.log"

    SendCommandToVM $vm "echo '##### LIS version #####'$'\n' >> generalinfo.log"
    SendCommandToVM $vm "modinfo hv_vmbus >> generalinfo.log"
    SendCommandToVM $vm "echo >> generalinfo.log && echo >> generalinfo.log"

    SendCommandToVM $vm "echo '##### Daemons status(ps uax) #####'$'\n' >> generalinfo.log"
    SendCommandToVM $vm "ps uax | grep hv.*daemon >> generalinfo.log"
    SendCommandToVM $vm "ps uax | grep hyper >> generalinfo.log"
    SendCommandToVM $vm "echo >> generalinfo.log && echo >> generalinfo.log"

    SendCommandToVM $vm "echo '##### System messages(syslog or messages) #####'$'\n' >> generalinfo.log"
    SendCommandToVM $vm "cat /var/log/messages >> generalinfo.log"
    SendCommandToVM $vm "cat /var/log/syslog >> generalinfo.log"
    SendCommandToVM $vm "echo >> generalinfo.log && echo >> generalinfo.log"

    SendCommandToVM $vm "echo '##### DMESG Driver messages #####'$'\n' >> generalinfo.log"
    SendCommandToVM $vm "dmesg >> generalinfo.log"
}

########################################################################
#
# DoCollectLogFiles()
#
########################################################################
function DoCollectLogFiles([System.Xml.XmlElement] $vm, [XML] $xmlData, [string] $collect)
{
    <#
    .Synopsis
        Collect files from the VM
    .Description
        Collect log file from the VM. Update th e-mail summary
        with the test results. Set the transition time.  Finally
        transition to FindNextAction to look at OnError, NoReboot,
        and our current state to determine the next action.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoCollectLogFiles $testVM $xmlData
    #>
    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoCollectLogFiles received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoCollectLogFiles($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoCollectLogFiles received a null or bad xmlData parameter - disabling VM"
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

    #
    # Update the e-mail summary
    #

    if ( ($($vm.testCaseResults) -eq $Passed) -or ($($vm.testCaseResults) -eq $Skipped))
    {
        $completionCode = $vm.testCaseResults
        $vm.individualResults = $vm.individualResults -replace ".$","1"
    }
    elseif ( ($($vm.testCaseResults) -eq $Failed) )
    {
        $completionCode = $Failed
    }
    else
    {
        $completionCode = $Aborted
    }

    $iterationMsg = $null
    if ($vm.iteration -ne "-1")
    {
        $iterationMsg = "($($vm.iteration))"
    }

    SetTestResult $currentTest $completionCode $xmlData

    $vm.emailSummary += ("    Test {0,-25} : {2}<br />" -f $($vm.currentTest), $iterationMsg, $completionCode)

    #
    # Collect test results
    #
    $logFilename = "$($vm.vmName)_${currentTest}_${iterationNum}.log"
    LogMsg 4 "Info : $($vm.vmName) collecting logfiles"
    if (-not (GetFileFromVM $vm "${currentTest}.log" "${testDir}\${logFilename}") )
    {
        LogMsg 0 "Error: $($vm.vmName) DoCollectLogFiles() is unable to collect ${logFilename}"
    }

    #
    # Test case may optionally create a summary.log.
    #
    $summaryLog = "${testDir}\$($vm.vmName)__${currentTest}_summary.log"
    del $summaryLog -ErrorAction "SilentlyContinue"
    GetFileFromVM $vm "summary.log" $summaryLog
    if (test-path $summaryLog)
    {
        $content = Get-Content -path $summaryLog
        foreach ($line in $content)
        {
            $vm.emailSummary += "          $line<br />"
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
            LogMsg 9 "Info : Get '${file}' from VM $($vm.vmName)."
            $dstFile = "$($vm.vmName)_${currentTest}_${file}"
            if (-not (GetFileFromVM $vm $file "${testDir}\${dstFile}") )
            {
                LogMsg 0 "Warn : $($vm.vmName) cannot copy '${file}' from VM"
            }
        }
    }

    if (($completionCode -eq $Aborted -or $completionCode -eq $Failed) -and $collect -eq "True")
    {
        LogMsg 4 "Info : $($vm.vmName) generating general logfile"
        GenerateGeneralLogFile $vm
        $generalLog = "$($vm.vmName)_${currentTest}_logs.log"
        if (-not (GetFileFromVM $vm "generalinfo.log" "${testDir}\${generalLog}") )
        {
            LogMsg 0 "Error: $($vm.vmName) DoCollectLogFiles() is unable to collect ${generalLog}"
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
    <#
    .Synopsis
        Run a post test PowerShell script.
    .Description
        If the currentTest defines a PostTest script, run it
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoRunPostTestScript $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        # This should never occur
        LogMsg 0 "Error: DoRunPostScript() was passed an bad VM object"
        return
    }

    LogMsg 9 "Info : DoRunPostScript( $($vm.vmName) )"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunPostTestScript received a null or bad xmlData parameter - terminating VM"
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
            #
            # If multiple PostTest scripts specified
            #
            if ($testData.postTest.file)
            {
                foreach ($script in $testData.postTest.file)
                {
                    LogMsg 3 "Info : $($vm.vmName) running Post Test script '${script}' for test $($testData.testName)"
                    $sts = RunPSScript $vm $script $xmlData "PostTest"
                    if (! $sts)
                    {
                        LogMsg 0 "Error: $($vm.vmName) PostTest script ${script} for test $($testData.testName) failed"
                    }
                }
            }
            else # Original syntax of <postTest>setupscripts\myPretest.ps1</postTest>
            {
                LogMsg 3 "Info : $($vm.vmName) - starting postTest script $($testData.postTest)"
                $sts = RunPSScript $vm $($testData.postTest) $xmlData "PostTest"
                if (-not $sts)
                {
                    LogMsg 0 "Error: VM $($vm.vmName) postTest script for test $($testData.testName) failed"
                    $vm.emailSummary += ("    Test {0, -25} : {1}<br />" -f $($testData.testName), "Failed - post script failed")
                }
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
########################################################################
function DoDetermineReboot([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Determine if the VM needs to be shutdown.
    .Description
        Determine if the VM needs to be shutdown before running
        the next test.  Look at OnError, NoReboot, and our current
        state to determine what our next state should be.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoDetermineReboot $testVm $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoDetermineReboot received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoDetermineReboot($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoDetermineReboot received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoDetermineReboot received a null xmlData parameter - disabling VM"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    $nextTest = GetNextTest $vm $xmlData
    $testData = GetTestData $vm.currentTest $xmlData
    $testResults = $false

    if ( ($($vm.testCaseResults) -eq $Passed) -or ($($vm.testCaseResults) -eq $Skipped) )
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
            #save currentTest name before update
            $currentTestName = $vm.currentTest
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
                SetRunningTime $currentTestName $vm
                #
                # Mark next test not rebooted
                #
                $vm.isRebooted = $false.ToString()

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
########################################################################
function DoShutdownSystem([System.Xml.XmlElement] $vm, [XML] $xmlData, [string] $noshutdown)
{
    <#
    .Synopsis
        Shutdown the VM
    .Description
        Use Hyper-V to request the VM to shutdown.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoShutdownSystem $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoShutdownSystem received a bad vm parameter"
        return
    }
     if ($noshutdown -eq "True") {
         LogMsg 0 "Info : NoShutdown parameter is True. Skipping DoShutdownSystem($($vm.vmName))"
     }
    else {
        LogMsg 9 "Info : DoShutdownSystem($($vm.vmName))"
    }

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoShutdownSystem received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoShutdownSystem received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    if ($noshutdown -eq "True") {
         UpdateState $vm $Finished
    }
    else {
        ShutDownVM $vm
        UpdateState $vm $ShuttingDown
    }
}

########################################################################
#
# DoShuttingDown()
#
########################################################################
function DoShuttingDown([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Verify the VM goes to a Hyper-V Off state
    .Description
        Verify the VM goes to a Hyper-V Off state.  If this state
        times out, force the VM to an Off state.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoShuttingDown $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoShuttingDown received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoShuttingDown($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoShuttingDown received a null or bad xmlData parameter - disabling VM"
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
    $v = Get-VM -Name $vm.vmName -ComputerName $vm.hvServer
    if ($v -eq $null)
    {
        LogMsg 0 "Error: ShutDownVM cannot find the VM $($vm.vmName) on HyperV server $($vm.hvServer) after testing"
        $vm.emailSummary += "VM $($vm.vmName) cannot be found in shutdown VM- no tests run on VM<br />"
        UpdateState $vm $Disabled
        return
    }
    if ($($v.State) -eq "Off")
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
            SetRunningTime $vm.currentTest $vm
            UpdateState $vm $SystemDown
        }
    }
}

########################################################################
#
# DoRunCleanUpScript()
#
########################################################################
function DoRunCleanUpScript($vm, $xmlData)
{
    <#
    .Synopsis
        Run a cleanup script
    .Description
        If the currentTest specified a cleanup script, run the
        script.  Setup and cleanup scripts are always PowerShell
        scripts.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoRunCleanUpScript $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoRunCleanupScript received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoRunCleanupScript($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoRunCleanupScript received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoRunCleanupScript received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #
    # We should never be called unless the VM is stopped
    #
    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
    if ($v.State -ne "Off")
    {
        LogMsg 0 "Error: $($vm.vmName) is not stopped to run cleanup script for test $($vm.currentTest) - terminating tests"
        LogMsg 0 "Error: The VM may be left in a running state."
        $vm.emailSummay += "VM not in a stopped state to run cleanup script - tests terminated<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
        return
    }

    #
    # Run cleanup script of one is specified.  Do not fail the test if the script
    # returns an error. Just log the error and condinue.
    #
    $currentTestData = GetTestData $($vm.currentTest) $xmlData
    if ($currentTestData -is [System.Xml.XmlElement] -and $currentTestData.cleanupScript)
    {
        #
        # If multiple cleanup scripts specified
        #
        if ($currentTestData.cleanupScript.file)
        {
            foreach ($script in $currentTestData.cleanupScript.file)
            {
                LogMsg 3 "Info : $($vm.vmName) running cleanup script '${script}' for test $($currentTestData.testName)"
                $sts = RunPSScript $vm $script $xmlData "Cleanup"
                if (! $sts)
                {
                    LogMsg 0 "Error: $($vm.vmName) cleanup script ${script} for test $($currentTestData.testName) failed"
                }
            }
        }
        else  # original syntax of <cleanupscript>setupscripts\myCleanup.ps1</cleanupscript>
        {
            LogMsg 3 "Info : $($vm.vmName) running cleanup script $($currentTestData.cleanupScript) for test $($currentTestData.testName)"

            $sts = RunPSScript $vm $($currentTestData.cleanupScript) $xmlData "Cleanup"
            if (! $sts)
            {
                LogMsg 0 "Error: $($vm.vmName) cleanup script $($currentTestData.cleanupScript) for test $($currentTestData.testName) failed"
            }
        }
    }
    else
    {
        LogMsg 0 "Error: $($vm.vmName) entered RunCleanupScript state when test $($vm.currentTest) does not have a cleanup script"
        $vm.emailSummary += "Entered RunCleanupScript but test does not have a cleanup script<br />"
    }

    SetRunningTime $vm.currentTest $vm
    UpdateState $vm $SystemDown
}

########################################################################
#
# DoForceShutDown()
#
########################################################################
function DoForceShutDown([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Stop the VM
    .Description
        If the VM is not in a Hyper-V off state, stop the VM.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoForceShutdown $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoForceShutdown received a null vm parameter"
        return
    }

    LogMsg 9 "Info : DoForceShutdown($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoForceShutdown received a null or bad xmlData parameter - disabling VM"
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

    $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
    if ( $($v.State) -eq "Off" )
    {
        SetRunningTime $vm.currentTest $vm
        UpdateState $vm $nextState
    }
    else
    {
        #
        # Try to force the VM to a stopped state
        #
        $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
        #Set-VMState -vm $v -state 3 # Set-VMState requires the integer value, not the enumerated [VMState]::Stopped value
        Stop-VM -Name $vm.vmName -ComputerName $vm.hvServer -Force -TurnOff

        while ($timeout -gt 0)
        {
            $v = Get-VM $vm.vmName -ComputerName $vm.hvServer
            if ( $($v.State) -eq "Off" )
            {
                SetRunningTime $vm.currentTest $vm
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
########################################################################
function DoFinished([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Finish up after the test run completed.
    .Description
        Finish up after the test run completed. Kill all remaining processes
        started by LIS automation.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoFinished
    #>

    LogMsg 11 "Info : DoFinished( $($vm.vmName), xmlData )"
    LogMsg 11 "Info :   timestamp = $($vm.stateTimestamp))"
    LogMsg 11 "Info :   Test      = $($vm.currentTest))"

    If ($vm.role.ToLower().StartsWith("sut"))
    {
        SaveResultToXML $testDir
    }
}

########################################################################
#
# DoStartPS1Test()
#
########################################################################
function DoStartPS1Test([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        Start a PowerShell test case script running
    .Description
        Some test cases run on the guest VM and others run
        on the Hyper-V host.  If the test case script is a
        PowerShell script, start it as a PowerShell job
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoStartPS1Test $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoStartPS1Test received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoStartPS1Test($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoStartPS1Test received a null or bad xmlData parameter - disabling VM"
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

    $vm.testCaseResults = $Aborted

    if (! (test-path $testScript))
    {
        $msg = "Error: $vmName PowerShell test script does not exist: $testScript"
        LogMsg 0 $msg
        $msg | out-file -encoding ASCII -append -filePath $logFilename

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
        $msg = "Creating Log File for : $testScript"
        $msg | out-file -encoding ASCII -append -filePath $logFilename

        #
        # Start the PowerShell test case script
        #
        LogMsg 3 "Info : $vmName Run PowerShell test case script $testScript"
        LogMsg 3 "Info : vmName: $vmName"
        LogMsg 3 "Info : hvServer: $hvServer"
        LogMsg 3 "Info : params: $params"

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
# DoWaitForDependencyVM()
#
########################################################################
function DoWaitForDependencyVM([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
    .Synopsis
        if XML defined nonSUT VMs, then wait for it is ready (System started and setup configuration completed, and the VM transited to Finish
    .Description
        Wait for all nonSUT VM finished the startup and configuration
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoWaitForDependencyVM $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoWaitForDependencyVM received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoWaitForDependencyVM($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoWaitForDependencyVM received a null or bad xmlData parameter - disabling VM"
        $vm.emailSummary += "DoWaitForDependencyVM received a null xmlData parameter - disabling VM<br />"
        $vm.currentTest = "done"
        UpdateState $vm $ForceShutdown
    }

    #if this is not a SUT VM, it should not wait for others.
    If ($vm.role.ToLower().StartsWith("nonsut"))
    {
         LogMsg 3 "Warn : DoWaitForDependencyVM() should not be called by a NonSUT VM"
         UpdateState $vm $Finished
    }
    else
    {
        #assume all NonSUT VM finished
        $allNonSUTVMFinished = $true
        foreach( $v in $xmlData.config.VMs.vm )
        {
            if ($vm.role.ToLower().StartsWith("nonsut"))
            {
                if ($($v.state) -ne $Finished)
                {
                    $allNonSUTVMFinished = $false
                }
            }
        }

        if ($allNonSUTVMFinished -eq $true)
        {
            UpdateState $vm $PushTestFiles
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
    <#
    .Synopsis
        Check if the PowerShell job running the test script has completed
    .Description
        Check if the PowerShell job running the test script has completed
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoPS1TestRunning $testVm $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPS1TestRunning received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoPS1TestRunning($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPS1TestRunning received a null or bad xmlData parameter - disabling VM"
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
        AbortCurrentTest $vm "bad or incorrect jobId for test $($vm.currentTest)"
        return
    }

    if ($jobStatus.State -eq "Completed")
    {
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
    <#
    .Synopsis
        Collect test results
    .Description
        When the PowerShell job running completes, collect the output
        of the test job, write the output to a logfile, and report
        the pass/fail status of the test job.
    .Parameter vm
        XML Element representing the VM under test
    .Parameter $xmlData
        XML document for the test
    .Example
        DoPS1TestCompleted $testVM $xmlData
    #>

    if (-not $vm -or $vm -isnot [System.Xml.XmlElement])
    {
        LogMsg 0 "Error: DoPS1TestCompleted received an bad vm parameter"
        return
    }

    LogMsg 9 "Info : DoPS1TestCompleted($($vm.vmName))"

    if (-not $xmlData -or $xmlData -isnot [XML])
    {
        LogMsg 0 "Error: DoPS1TestCompleted received a null or bad xmlData parameter - disabling VM"
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
    $completionCode = $Failed
    $jobID = $vm.jobID
    if ($jobID -ne "none")
    {
        $error.Clear()
        $jobResults = @(Receive-Job -id $jobID -ErrorAction SilentlyContinue)
        if ($jobResults)
        {
            if ($error.Count -gt 0)
            {
                "Error: ${currentTest} script encountered an error"
                $error[0].Exception.Message | out-file -encoding ASCII -append -filePath $logFilename
            }

            foreach ($line in $jobResults)
            {
                if ($line -ne $null)
                {
                    $line | out-file -encoding ASCII -append -filePath $logFilename
                }
                else
                {
                    $line >> $logFilename
                }
            }

            #
            # The last object in the $jobResults array will be the boolean
            # value the script returns on exit.  See if it is true.
            #
            if ($jobResults[-1] -eq $Passed -or $jobResults[-1] -eq $true)
            {
                $completionCode = $Passed
                $vm.testCaseResults = $Passed
                $vm.individualResults = $vm.individualResults -replace ".$","1"
            }
            elseif ($jobResults[-1] -eq $Skipped)
            {
                $completionCode = $Skipped
                $vm.testCaseResults = $Skipped
                $vm.individualResults = $vm.individualResults -replace ".$","1"
            }
            elseif ($jobResults[-1] -eq $Aborted)
            {
                $completionCode = $Aborted
                $vm.testCaseResults = $Aborted
            }
        }

        if ($collect -eq "True" -and ($completionCode -eq $Failed -or $completionCode -eq $Aborted) -and (Get-VM -name $vm.vmName -ComputerName $vm.hvServer).State -eq "Running")
 		{
			LogMsg 4 "Info : $($vm.vmName) generating general logfile"
			GenerateGeneralLogFile $vm
			$generalLog = "$($vm.vmName)_${currentTest}_logs.log"
			if (-not (GetFileFromVM $vm "generalinfo.log" "${testDir}\${generalLog}"))
			{
				LogMsg 0 "Error: $($vm.vmName) DoCollectLogFiles() is unable to collect ${generalLog}"
			}
			else
			{
 				LogMsg 1 "Info: Debug file can be found at ${testDir}\${generalLog}"
			}
		}

        Remove-Job -Id $jobID
    }

    LogMsg 0 "Info : ${vmName} Status for test $($vm.currentTest) = ${completionCode}"

    SetTestResult $currentTest $completionCode $xmlData
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
            $vm.emailSummary += "          ${line}<br />"
        }
        del $summaryLog
    }

    # UpdateState $vm $DetermineReboot
    $testData = GetTestData $currentTest $xmlData
    if ( $($testData.postTest) )
    {
        UpdateState $vm $RunPostTestScript
    }
    else
    {
        UpdateState $vm $DetermineReboot
    }
}
0
