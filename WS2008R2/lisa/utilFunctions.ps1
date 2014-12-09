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


#####################################################################
#
# HasItBeenTooLong
#
#####################################################################
function HasItBeenTooLong([String] $timestamp, [Int] $timeout)
{
    <#
	.Synopsis
    	Check to see if a timeout has occured.
        
    .Description
        Convert the timestamp from a string to a [DateTime] type,
        add in the timeout value and see if it is less than the
        current date/time.
        
	.Parameter timestamp
    	A string representing the timestamp
        Type : [String]
        
    .Parameter timeout
        An integer timeout period in seconds.
        Type : [Int]
        
    .ReturnValue
        Return $True if current time is greater than timestamp + timeout,
               $false otherwise.
        Output type : [Boolean]
        
    .Example
        HasItBeenTooLong $myTimeStamp $myTimeOut
	#>
    
    $retVal = $false

    if (-not $timeStamp)
    {
        # Bad data - force a timeout
        return $True    
    }

    if (-not $timeout)
    {
        # Bad data - force a timeout
        return $True
    }

    if ($timeout -le 0)
    {
        # Bad data - force a timeout
        return $True
    }

    $now = [DateTime]::Now
    $ts = [DateTime]::Parse($timestamp)
    $tooLong = [DateTime]::Compare($ts.AddSeconds($timeout), $now)

    if ($tooLong -eq -1)
    {
        $retVal = $true
    }

    return $retVal
}


#####################################################################
#
# GetNextTest
#
#####################################################################
function GetNextTest([System.Xml.XmlElement] $vm, [xml] $xmlData)
{
    <#
	.Synopsis
    	Get the name of the next test the VM is to run
        
    .Description
        Examine the $vm.suite field and then walk through the test suite
        to return the string name of the next test the VM is to perform.
        If all tests have been performed, return the string "done".
        
	.Parameter vm
    	An XML element representing the VM
        Type : [System.Xml.XmlElement]
        
    .ReturnValue
        A string of the name of the next test.
        Output type : [Boolean]
        
    .Example
        GetNextTest $myVM
	#>
    LogMsg 9 "Info :    GetNextText($($vm.vmName))"
    LogMsg 9 "Debug:      vm.currentTest = $($vm.currentTest)"
    LogMsg 9 "Debug:      vm.suite = $($vm.suite)"
    
    $done = "done"      # Assume no more tests to run
    
    if (-not $vm)
    {
        LogMsg 0 "Error: GetNextTest() received a null VM parameter"
        return $done
    }
    
    if (-not $xmlData)
    {
        LogMsg 0 "Error: GetNextTest() received a null xmlData parameter"
        return $done
    }

    if ($vm.currentTest -eq $done)
    {
        return $done
    }

    if (-not $xmlData.config.testSuites.suite)
    {
        LogMsg 0 "Error: no test suites defined in .xml file"
        return $done
    }

    $tests = $null
    $nextTest = $done
    
    foreach ($suite in $xmlData.config.testSuites.suite)
    {
        if ($suite.suiteName -eq $vm.suite)
        {
            if ($suite.suiteTests)
            {
                $tests = $suite.suiteTests
            }
            else
            {
                LogMsg 0 "Error: Test suite $($ts.name) does not have any tests"
                return $done
            }
            break
        }
    }

    #
    # We found the tests for the VMs test suite. Next find the next test
    # to run.  If we are iterating the current test, and there are more
    # iterations to run, just return the current test.
    #
    if ($tests)
    {
        $prev = "unknown"
        $currentTest = $vm.currentTest
        foreach ($t in $tests.suiteTest)
        {
            if ($currentTest -eq "none")
            {
                $nextTest = [string] $t
                break
            }
            
            if ($currentTest -eq $prev)
            {
                $nextTest = [string] $t
                break
            }
            $prev = $t
        }
    }
        
    if ($vm.iteration -ne "-1")
    {
        if ($vm.currentTest -eq "none" -or $vm.currentTest -eq "done")
        {
            LogMsg 0 "Error: $($vm.vmName) has a non zero iteration count for test $($vm.currentTest)"
            return $done
        }
        
        $testData = GetTestData $vm.currentTest $xmlData
        if ($testData)
        {
            if ($testData.maxIterations)
            {
                $iterationNumber = [int] $vm.iteration
                $maxIterations = [int] $testData.maxIterations
                if ($iterationNumber -lt $maxIterations)
                {
                    #
                    # There are more iterations, so return current test
                    #
                    $nextTest = [string] $vm.currentTest
                }
            }
            else
            {
                LogMsg 0 "Error: $($vm.vmName) has a none zero iteration count, but test $($vm.currentTest) does not have maxIterations"
                return $done
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) cannot find test data for test $($vm.currentTest)"
            return $done
        }
    }

    return $nextTest
}


#####################################################################
#
# GetTestData
#
#####################################################################
function GetTestData([String] $testName, [xml] $xmlData)
{
    <#
	.Synopsis
    	Retrieve the xml object for the specified test
        
    .Description
        Find the test named $testName, and return the xml element
        for that test, on $null if the test is not found.
        
	.Parameter testName
    	The name of the test to return
        Type : [String]
        
    .ReturnValue
        An xml element of the specific test
        Output type: [System.Xml.XmlElement]
    .Example
        GetTestData "MyTest"
	#>
    LogMsg 6 ("Info :    GetTestData($($testName))")
    
    $testData = $null

    foreach ($test in $xmlData.config.testCases.test)
    {
        if ($test.testName -eq $testName)
        {
            $testData = $test
            break
        }
    }

    return $testData
}



#####################################################################
#
# GetTestTimeout
#
#####################################################################
function GetTestTimeout([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    <#
	.Synopsis
    	Retrieve timeout value for the VM's current test
        
    .Description
        Return the timeout value defined in the .xml file for
        the current test, or $null if no timeout is specified.
        
	.Parameter vm
    	The xml element of the virtual machine
        Type : [System.Xml.XmlElement]
        
    .ReturnValue
        A string representing the timeout value in seconds,
        or $null if not timeout is found.
        Output type: [String]
    .Example
        GetTestTimeout $myVM
	#>
    
    $timeout = $null
    $testData = GetTestData $vm.currentTest $xmlData

    if ($testData.timeout)
    {
        $timeout = [string] $testData.timeout
    }

    return $timeout
}


#####################################################################
#
# AbortCurrentTest
#
#####################################################################
function AbortCurrentTest([System.Xml.XmlElement] $vm, [string] $msg)
{
    <#
	.Synopsis
    	Mark the current test as aborted.
        
    .Description
        Displayed msg if provided, set the VM's testCaseResults to 
        "False", and set the VM's state to completed, update the
        VM's timestamp
        
	.Parameter vm
    	The xml element of the virtual machine
        Type : [System.Xml.XmlElement]

    .Parameter msg
        A string to be included in the ICA log.
        Type : [String]
        
    .ReturnValue
        none
        
    .Example
        AbortCurrentTest $myVM "This is just a test"
	#>

    #$TestAborted = "TestAborted"

    if ($null -ne $msg)
    {
        logMsg 0 "Error: $($vm.vmName) $msg"
    }

    $vm.testCaseResults = "False"
    $vm.state = $CollectLogFiles
    
    logMsg 2 "Info : $($vm.vmName) transitioned to state $($vm.state)"
    $vm.stateTimestamp = [DateTime]::Now.ToString()
}


#####################################################################
#
# SummaryToString
#
#####################################################################
function SummaryToString([XML] $xmlConfig, [DateTime] $startTime, [string] $xmlFilename)
{
    <#
	.Synopsis
    	Append the summary text from each VM into a single string.
        
    .Description
        Append the summary text from each VM one long string. The
        string includes line breaks so it can be display on a 
        console or included in an e-mail message.
        
	.Parameter xmlConfig
    	The parsed xml from the $xmlFilename file.
        Type : [System.Xml]

    .Parameter startTime
        The date/time the ICA test run was started
        Type : [DateTime]

    .Parameter xmlFilename
        The name of the xml file for the current test run.
        Type : [String]
        
    .ReturnValue
        A string containing all the summary message from all
        VMs in the current test run.
        
    .Example
        SummaryToString $testConfig $myStartTime $myXmlTestFile
	#>
    
    $str = "<br />Test Results Summary<br />"
    $str += "LISA test run on " + $startTime
    $str += "<br />XML file: $xmlFilename<br /><br />"
    
    #
    # Add information about the host running ICA to the e-mail summary
    #
    $str += "<pre>"
    foreach($vm in $xmlConfig.config.VMs.vm)
    {
        $str += $vm.emailSummary + "<br />"
    }
	 
	$fname = [System.IO.Path]::GetFilenameWithoutExtension($xmlFilename)
	
	$hostname = hostname
    
	$str += "Logs can be found at \\$($hostname)\LisaTestResults\" + $fname + "-" + $startTime.ToString("yyyyMMdd-HHmmss") + "<br /><br />"
	
    $str += "</pre><br />"

    return $str
}


#####################################################################
#
# SendEmail
#
#####################################################################
function SendEmail([XML] $xmlConfig, [DateTime] $startTime, [string] $xmlFilename)
{
    <#
	.Synopsis
    	Send an e-mail message with test summary information.
        
    .Description
        Collect the test summary information from each VM.  Send an
        eMail message with this summary information to emailList defined
        in the xml config file.
        
	.Parameter xmlConfig
    	The parsed XML from the test xml file
        Type : [System.Xml]
        
    .ReturnValue
        none
        
    .Example
        SendEmail $myConfig
	#>

    $to = @()
    foreach($r in $xmlConfig.config.global.email.recipients.to)
    {
        $to = $to + $r
    }
    
    $from = $xmlConfig.config.global.email.Sender
    $subject = $xmlConfig.config.global.email.Subject + " " + $startTime
    $smtpServer = $xmlConfig.config.global.email.smtpServer
    $fname = [System.IO.Path]::GetFilenameWithoutExtension($xmlFilename)
    
    $body = SummaryToString $xmlConfig $startTime $fname
    $body = $body.Replace("Aborted", '<em style="background:Yellow; color:Red">Aborted</em>')
    $body = $body.Replace("Failed", '<em style="background:Yellow; color:Red">Failed</em>')

    # TODO: remove hard coded log file directory
    $hostname = hostname
    $str += "Logs can be found at \\$($hostname)\Public\LisaTestResults\" + $fname + "-" + $startTime.ToString("yyyyMMdd-HHmmss") + "<br /><br />"

    Send-mailMessage -to $to -from $from -subject $subject -body $body -BodyAsHtml -smtpserver $smtpServer
}


#####################################################################
#
# ShutDownVM
#
#####################################################################
function ShutDownVM([System.Xml.XmlElement] $vm)
{
    <#
	.Synopsis
    	Stop the VM
        
    .Description
        Try to send a halt command to the VM.  If this fails,
        use the HyperV library Stop-VM call to try and stop
        the VM.  If the VM is already stopped, do nothing.
        
	.Parameter vm
    	An xml node representing the VM.
        Type : [System.Xml.XmlElement]
        
    .ReturnValue
        none
        
    .Example
        ShutDownVM $myVM
	#>

    $v = Get-VM -vm $($vm.vmName) -server $($vm.hvServer)
    if ($($v.EnabledState) -ne 3)
    {
        if (-not (SendCommandToVM $vm "init 0") )
        {
            LogMsg 0 "Warn : $($vm.vmName) could not send shutdown command to the VM. Using HyperV to stop the VM."
            Stop-VM $vm 
        }
    }
}



#####################################################################
#
# RunPSScript
#
#####################################################################
function RunPSScript([System.Xml.XmlElement] $vm, [string] $scriptName, [XML] $xmlData, [string] $mode, [string] $logFilename)
{
    <#
	.Synopsis
    	Run a separate PowerShell script.
        
    .Description
        Run the specified PowerShell script.
        
	.Parameter vmName
    	Name of the VM
        Type : [String]

    .Parameter scriptName
        Name of the PowerShell script to be run
        Type : [String]

    .Parameter logFilename
        The name of the file to write output to.
        Type : [String]

    .ReturnValue
        True or false to indicate if the script ran successfully or not.
        Output type: [Boolean]

    .Example
        RunPSScript "fed13" "hvServer1" ".\AddNic.ps1" $testData ".\myLog.log"
	#>

    $retVal = $False

    $scriptMode = "unknown"

    #
    # Check the input arguments
    #
    if (-not $vm)
    {
        logMsg 0 "Error: RunPSScript() was passed a numm VM"
        return $False
    }

    if (-not $scriptName)
    {
        logMsg 0 ("Error: RunPSScript($vmName, $hvServer, null) was passed a null scriptName")
        return $False
    }

    if (-not $xmlData)
    {
        logMsg 0 ("Error: RunPSScript($vmName, $hvServer, $scriptName, testData, null) was passed null test data")
        return $False
    }

    if ($mode)
    {
        $scriptMode = $mode
    }

    if (-not (test-path -path $scriptName))
    {
        logMsg 0 ("Error: RunPSScript() script file '$scriptName' does not exist.")
        return $False
    }

    logMsg 6 ("Info : RunPSScript($vmName, $hvServer, $scriptName")

    $vmName = $vm.vmName
    $hvServer = $vm.hvServer
    $testData = GetTestData $vm.currentTest $xmlData
    
    if (-not $testData)
    {
        LogMsg 0 "$($vm.vmName) Unable to collect test data for test $($vm.currentTest)"
        return $False
    }

    #
    # Create an string of test params, separated by semicolons - ie. "a=1;b=x;c=5;"
    #
    $params = CreateTestParamString $vm $xmlData
    $params += "scriptMode=${scriptMode};"

    #
    # Invoke the setup/cleanup script
    #
    $cmd = "powershell -file $scriptName -vmName $vmName -hvServer $hvServer"

    #
    # Only add the testParams if something was specified, and it appears reasonable
    # Min param length is 3 -ie.  "a=1"
    #
    if ($params.Length -gt 2 -and $params.Contains("="))
    {
        $cmd += " -testParams `"$params`""
    }

    LogMsg 6 ("Info : Invoke-Expression $cmd")
    $sts = Invoke-Expression $cmd

    $numItems = $sts.length
    LogMsg 6 "Debug: $vmName - Invoke-Expression returned array with $($sts.length) elements"

    if ($sts[$numItems - 1] -eq "True")
    {
        $retVal = $true
    }

    #
    # Write script output into log file
    #    
    for($i=0; $i -lt $numItems-1; $i++)
    {
        logMsg 3 ("Info :         $vmName - $($sts[$i])")
        if ($logFilename)
        {
            $($sts[$i]) | out-file -append $logFilename
        }
    }

    return $retVal
}


#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
	<#
	.Synopsis
    	Check to see if a specific TCP port is open on a server.
    .Description
        Try to create a TCP connection to a specific port (22 by default)
        on the specified server. If the connect is successful return
        true, false otherwise.
	.Parameter Host
    	The name of the host to test
    .Parameter Port
        The port number to test. Default is 22 if not specified.
    .Parameter Timeout
        Timeout value in seconds
    .Example
        Test-Port $serverName
    .Example
        Test-Port $serverName -port 22 -timeout 5
	#>

    $retVal = $False
    $timeout = $to * 1000

    #
    # Try an async connect to the specified machine/port
    #
    $tcpclient = new-Object system.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($serverName,$port,$null,$null)

    #
    # Wait for the connect to complete. Also set a timeout
    # so we don't wait all day
    #
    $connected = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

    # Check to see if the connection is done
    if($connected)
    {
        #
        # Close our connection
        #
        try
        {
            $sts = $tcpclient.EndConnect($iar)
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
            $msg = $_.Exception.Message
        }

        #if($sts)
        #{
        #    $retVal = $true
        #}
    }
    $tcpclient.Close()

    return $retVal
}


#####################################################################
#
# UpdateState
#
#####################################################################
function UpdateState([System.Xml.XmlElement] $vm, [string] $newState)
{
	<#
	.Synopsis
    	Update the VM's state in the XML object representing the VM.
    .Description
        Update the VMs state in the XML object, log a message,
        and update the timestamp of the last state transition.
	.Parameter vm
    	The XML object representing the VM who's state needs updating.
    .Parameter newState
        The VMs new state.
    .ReturnValue
        None
	#>
    
    $oldState = $vm.state
    $vm.state = $newState
    LogMsg 2 "Info : $($vm.vmName) transitioned from ${oldState} to $($vm.state)"
    $vm.stateTimestamp = [DateTime]::Now.ToString()
}


#####################################################################
#
# GetFileFromVM()
#
#####################################################################
function GetFileFromVM([System.Xml.XmlElement] $vm, [string] $remoteFile, [string] $localFile)
{
	<#
	.Synopsis
    	Copy a file from a remote system, the VM, to a local copy.
    .Description
        Use SSH to copy a file from a remote system, to a local file,
        possibly renaming the file in the process.
	.Parameter vm
    	The XML object representing the VM to copy from.
    .Parameter remoteFile
        The name, including path, of the file on the remote system.
    .Parameter localFile
        The name, including path, the file is to be copied to.
    .ReturnValue
        True if the file was successfully copied, false otherwise.
	#>

    $retVal = $False

    $vmName = $vm.vmName
    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

    #bin\pscp -q -i ssh\${sshKey} root@${hostname}:${remoteFile} $localFile
    #if ($?)
    
    $process = Start-Process bin\pscp -ArgumentList "-i ssh\${sshKey} root@${hostname}:${remoteFile} ${localFile}" -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }

    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}


#####################################################################
#
# SendFileToVM()
#
#####################################################################
function SendFileToVM([System.Xml.XmlElement] $vm, [string] $localFile, [string] $remoteFile)
{
	<#
	.Synopsis
    	Copy a file To a remote system, the VM, to a local copy.
    .Description
        Use SSH to copy a file to a remote system.
	.Parameter vm
    	The XML object representing the VM to copy from.
    .Parameter localFile
        The name of the file is to be copied to the remote system.
    .Parameter remoteFile
        The name, including path, of the file on the remote system.
    .ReturnValue
        True if the file was successfully copied, false otherwise.
	#>

    $retVal = $False

    $vmName = $vm.vmName
    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

    $recurse = ""
    if (test-path -path $localFile -PathType Container )
    {
        $recurse = "-r"
    }
            
    #bin\pscp -q $recurse -i ssh\${sshKey} $localFile root@${hostname}:${remoteFile}
    #if ($?)

    $process = Start-Process bin\pscp -ArgumentList "-i ssh\${sshKey} ${localFile} root@${hostname}:${remoteFile}" -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }

    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}


#####################################################################
#
# SendCommandToVM()
#
#####################################################################
function SendCommandToVM([System.Xml.XmlElement] $vm, [string] $command)
{
    <#
        .Synopsis
            Execute a command on a remote system.
        .Description
            Use SSH to execute a command on a remote system.
        .Parameter vm
            The XML object representing the VM to copy from.
        .Parameter command
            The command to be executed on the remote system.
        .ReturnValue
            True if the file was successfully copied, false otherwise.
    #>

    $retVal = $False

    $vmName = $vm.vmName
    $hostname = $vm.ipv4
    $sshKey = $vm.sshKey

#    $dataSink = bin\plink -i ssh\${sshKey} root@${hostname} $command 2> out-null
#    if ($?)

    $process = Start-Process bin\plink -ArgumentList "-i ssh\${sshKey} root@${hostname} ${command}" -PassThru -NoNewWindow -Wait -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
    if ($process.ExitCode -eq 0)
    {
        $retVal = $True
    }
    else
    {
        LogMsg 0 "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    del lisaOut.tmp -ErrorAction "SilentlyContinue"
    del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}
 

#####################################################################
#
# TestRemotePath
#
#####################################################################
function TestRemotePath ([String] $path, [String] $hvServer)
{
	<#
	.Synopsis
    	Check to see if a file exists on a remote HyperV server
    .Description
        User WMI to see if a file exists on a remote HyperV server
	.Parameter path
    	The name of the host to test
    .Parameter hvServer
        The name, or IP address, of the HyperV server
    .Example
        TestRemoteFile "C:\HyperV\VHDs\test.vhd" "myHvServer"
    .Example
        TestRemoteFile -path "C:\HyperV\VHDs\test.vhd" -hvServer "myHvServer"
	#>

    $retVal = $False

    if (-not $path)
    {
        return $False
    }

    if (-not $hvServer)
    {
        return $False
    }

    #
    # Create a FileInfo object from the path string
    #
    try
    {
        $fileInfo = [System.IO.FileInfo]"$path"
        if (-not $fileInfo)
        {
            return $False
        }
    }
    catch
    {
        return $False
    }

    #
    # The WMI call requires the filename to be broken up into the following components:
    #     drive
    #     directory path
    #     filename
    #     filename extension
    #
    $fileName = $fileInfo.BaseName
    $extension = $null
    if ( ($fileInfo.Extension).Length -gt 1)
    {
        $extension = ($fileInfo.Extension).SubString(1)
    }
    
    $directory = $null
    if ( ($fileInfo.DirectoryName).Length -gt 0 )
    {
        $directory = $fileInfo.DirectoryName + "\"
    }
    
    $elements = $directory.Split(":")
    if ($elements -isnot [array])
    {
        return $False
    }

    if ($elements.Length -ne 2)
    {
        return $False
    }

    $drive = $elements[0] + ":"
    if ($drive.Length -ne 2)
    {
        return $False
    }

    #
    # The WMI call requires the directory path have double spaces - i.e.
    #   \\dir\\subdir\\subdir\\
    #
    $dirPath = ($elements[1]).Replace("\", "\\")

    $filter = "drive=`"$drive`""
    if ($dirPath)
    {
        $filter += " and path=`"$dirPath`""
    }
    
    if ($fileName)
    {
        $filter += " and filename=`"$fileName`""
    }
    
    if ($extension)
    {
        $filter += " and extension=`"$extension`""
    }
    
    #"Info : TestRemotePath filter = $filter"

    $fileInfo = gwmi CIM_dataFile -filter $filter -computer $hvServer

    if ($fileInfo)
    {
        $retVal = $True
    }

    return $retVal
}


#####################################################################
#
# TestRemotePath
#
#####################################################################
function Test-Admin ()
{
	<#
	.Synopsis
    	Check if process is running as an Administrator
    .Description
        Test if the user context this process is running as
        has Administrator privileges
    .Example
        Test-Admin
	#> 
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}




#######################################################################
#
# CreateTestParamString()
#
#######################################################################
function CreateTestParamString([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    $tp = ""

    $testData = GetTestData $($vm.currentTest) $xmlData

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
                $tp += $param + ";"
            }
        }
        
        #
        # Next, add any test specific testParams
        #
        if ($testdata.testParams)
        {
            LogMsg 9 "Info : $($vm.vmName) Adding testparmas for test $($testData.testName)"
            foreach ($param in $testdata.testParams.param)
            {
                $tp += $param + ";"
            }
        }
        
        #
        # Now, add VM specific testParams
        #
        if ($vm.testParams)
        {
            LogMsg 9 "Info : $($vm.vmName) Adding VM specific params"
            foreach ($param in $vm.testParams.param)
            {
                $tp += $param + ";"
            }
        }
    }
    
    #
    # Add the iteration information if test case is being iterated
    #
    if ($vm.iteration -ne "-1")
    {
        $iterationParam = GetIterationParam $vm $xmlData
        if ($iterationParam)
        {
            $tp += "iteration=$($vm.iteration);"
            
            if ($iterationParam -ne "")
            {
                $tp += "iterationParam=${iterationParam};"
            }
        }
        else
        {
            LogMsg 0 "Error: $($vm.vmName) Invalid iteration param for test $($vm.currentTest)"
        }
    }

    return $tp
}


#######################################################################
#
# UpdateCurrentTest()
#
# Description:
#
#######################################################################
function UpdateCurrentTest([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    if (-not $vm)
    {
        LogMsg 0 "Error: UpdateCurrentTest() received a null VM object"
        return
    }
    
    if (-not $xmlData)
    {
        LogMsg 0 "Error: UpdateCurrentTest() received a null xmlData object"
        return
    }
    
    $currentTest = $vm.currentTest
    if ($currentTest -eq "done")
    {
        return
    }
    
    $currentTestData = GetTestData $currentTest $xmlData
    $nextTest = $currentTest
    
    if ($vm.testCaseResults -eq "False" -and $currentTestData.onError -eq "Abort")
    {
        $vm.currentTest = "done"
        return
    }
    
    if ($currentTestData.maxIterations)
    {
         $iterationCount = (([int] $vm.iteration) + 1)
         $vm.iteration = $iterationCount.ToString()
         if ($iterationCount -ge [int] $currentTestData.maxIterations)
         {
             $nextTest = GetNextTest $vm $xmlData
             $vm.currentTest = [string] $nextTest
             $testData = GetTestData $vm.currentTest $xmlData
             if ($testData.maxIterations)
             {
                 $vm.iteration = "0"
             }
             else
             {
                 $vm.iteration = "-1"
             }
         }
    }
    else
    {
        $nextTest = GetNextTest $vm $xmlData
        $vm.currentTest = [string] $nextTest
        $testData = GetTestData $vm.currentTest $xmlData
        if ($testData.maxIterations)
        {
            $vm.iteration = "0"
        }
        else
        {
            $vm.iteration = "-1"
        }
    }
}


#######################################################################
#
# GetIterationparam()
#
# Description:
#
# Return:
#     $null   : on error
#     ""      : if no iteration param
#     "param" : if valid iteration param
#
#######################################################################
function GetIterationParam([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    $iterationParam = $null

    if (-not $VM)
    {
        LogMsg 0 "Error: GetIterationParam() received a null VM object"
        return $null
    }
    
    if (-not $xmlData)
    {
        LogMsg 0 "Error: GetIterationParam() received a null xmlData object"
        return $null
    }

    $testData = GetTestData $vm.currentTest $xmlData
    if ($testData)
    {
        if ($testData.maxIterations)
        {
            $iterationParam = ""
            
            if ($testData.iterationParams)
            {
                if ($testData.iterationParams.param.count -eq 1)
                {
                    $iterationParam = $testData.iterationParams.param
                }
                else
                {
                    if ($testData.iterationParams.param.count -eq $testData.maxIterations)
                    {
                        $iterationNumber = [int] $vm.iteration
                        $iterationParam = ($testData.iterationParams.param[$iterationNumber]).ToString()
                    }
                    else
                    {
                        LogMsg 0 "Error: GetIterationParam() incorrect number of iterationParams for test $($vm.currentTest)"
                        $iterationParam = $null
                    }
                }
            }
        }
        else
        {
            LogMsg 0 "Error: GetIterationParam() was called for a non-iterated test case"
        }
    }
    else
    {
        LogMsg 0 "Error: GetIterationParam() could not find test data for test $($vm.currentTest)"
    }

    return $iterationParam   
}

