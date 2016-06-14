#####################################################################
<#
.Synopsis
    Check time drift before and after reboot for many times.

.Description
    Get time drift, then reboot for many times, then get time drift, finally
    check difference between the two time drifts is very slight. The XML test
     case definition for this test would look similar to:
     <test>
         <testName>TimeDrift_RebootVM</testName>
         <testScript>SetupScripts\TK_timedrift_rebootVM.ps1</testScript>
         <files>remote-scripts\ica\auto_rdos_Reboot.sh</files>
         <files>remote-scripts\ica\AUTO_Reboot.sh</files>
         <timeout>2000</timeout>
         <onERROR>Continue</onERROR>
         <noReboot>False</noReboot>
         <testparams>
             <param>TC_COVERED=CORE-28</param>
             <param>REBOOT_COUNT=1</param>
         </testparams>
       </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams
    A semicolon separated list of test parameters.

.Example

#>
#####################################################################

param ([String] $vmName, [String] $hvServer, [String] $testParams)

#####################################################################
#
#   GetUnixVMTime()
#
#####################################################################
function GetUnixVMTime([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }

    $unixTimeStr = $null
    $command =  "date '+%m/%d/%Y%t%T%p ' -u"

    $sshKeyPath = Resolve-Path $sshKey
    $unixTimeStr = .\bin\plink.exe -i ${sshKeyPath} root@${ipv4} $command

    if (-not $unixTimeStr -and $unixTimeStr.Length -lt 20)
    {
        return $null
    }

    return $unixTimeStr
}
#####################################################################
#
#   GetTimeSync()
#
#####################################################################
function GetTimeSync([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }
    #
    # Get a time string from the VM, then convert the Unix time string into a .NET DateTime object
    #
    $unixTimeStr = GetUnixVMTime -sshKey "ssh\${sshKey}" -ipv4 $ipv4
    if (-not $unixTimeStr)
    {
       "ERROR: Unable to get date/time string from VM"
        return $False
    }

    $unixTime = [DateTime]::Parse($unixTimeStr)

    #
    # Get our time
    #
    $windowsTime = [DateTime]::Now.ToUniversalTime()

    #
    # Compute the timespan, then convert it to the absolute value of the total difference in seconds
    #
    $diffInSeconds = $null
    $timeSpan = $windowsTime - $unixTime
    if ($timeSpan)
    {
        $diffInSeconds = [Math]::Abs($timeSpan.TotalSeconds)
    }

    #
    # Display the data
    #
    #"Windows time: $($windowsTime.ToString())"
    #"Unix time: $($unixTime.ToString())"
    #"Difference: $diffInSeconds"
    #
    # Write-Output "Time difference = ${diffInSeconds}" | Out-File -Append $summaryLog
     return $diffInSeconds
}

#######################################################################
#
# Runs a remote script on the VM and returns the log.
#
#######################################################################
function RunRemoteScript1($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestFailed   = "TestFailed"
    $TestRunning   = "TestRunning"
    $timeout       = 6000

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }

     .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}"
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh"

    # Return the state file
    while ($timeout -gt 0 )
    {
        if ( TestPort $ipv4 )
        {
            # clean state.txt
            del state.txt -ERRORAction "SilentlyContinue"

            .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
            $sts = $?
            if ($sts)
            {
                if (test-path $stateFile)
                {
                    $contents = Get-Content -Path $stateFile
                    if ($null -ne $contents)
                    {
                            if ($contents -eq $TestRunning)
                            {
                                Write-Output "INFO : state file contains TestRunning."
                                Start-Sleep -seconds 10
                                $timeout -= 10
                                continue
                            }
                            elseif ($contents -eq $TestCompleted)
                            {
                                Write-Output "INFO : state file contains Testcompleted."
                                $retValue = $True
                                break
                            }

                            elseif ($contents -eq $TestAborted)
                            {
                                 Write-Output "INFO : State file contains TestAborted message."
                                 break
                            }
                            elseif ($contents -eq $TestFailed)
                            {
                                Write-Output "INFO : State file contains TestFailed message."
                                break
                            }

                            if ($timeout -eq 0)
                            {
                                Write-Output "ERROR : Timed out on Test Running , Exiting test execution."
                                break
                            }

                    }
                    else
                    {
                        Write-Output "Warn : state file is empty"
                        break
                    }

                }
                else
                {
                     Write-Host "Warn : ssh reported success, but state file was not copied"
                     break
                }
            }
            else
            {
                 Write-Output "ERROR : pscp exit status = $sts"
                 Write-Output "ERROR : unable to pull state.txt from VM."
                 break
            }
          }
        else
        {
            Start-Sleep -seconds 10
            $timeout -= 10
        }
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"

    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} .
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"
                    }

                    else
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"
                    }

            }
            else
            {
                Write-Output "Warn: $remoteScriptLog is empty"
            }
        }
        else
        {
             Write-Output "Warn: ssh reported success, but $remoteScriptLog file was not copied"
        }
    }

    # Cleanup
    del state.txt -ERRORAction "SilentlyContinue"
    del runtest.sh -ERRORAction "SilentlyContinue"

    return $retValue
}

#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "ERROR: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "ERROR: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "ERROR: testParams argument is null"
    return $False
}

#
# Parse the testParams string
#
$sshKey = $null
$ipv4 = $null
$rootDir = $null

$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        # Just ignore it
        continue
    }

    $val = $tokens[1].Trim()

    switch($tokens[0].Trim().ToLower())
    {
    "sshkey"  { $sshKey = $val }
    "ipv4"    { $ipv4 = $val }
    "rootdir" { $rootDir = $val }
    "TC_COVERED" { $tcCovered = $val }
    "REBOOT_COUNT" { $reboot_count = $val }
    default  { continue }
    }
}

#
# Make sure the required testParams were found
#
if (-not $sshKey)
{
    "ERROR: testParams is missing the sshKey parameter"
    return $False
}

if (-not $ipv4)
{
    "ERROR: testParams is missing the ipv4 parameter"
    return $False
}

"  sshKey  = ${sshKey}"
"  ipv4    = ${ipv4}"
"  rootDir = ${rootDir}"
"tcCovered = ${tcCovered}"
#
# Change the working directory
#
if (-not (Test-Path $rootDir))
{
    "ERROR: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ERRORAction SilentlyContinue
Write-Output "Covers ${tcCovered}" | Out-File $summaryLog

$diffInSeconds1 = $null
$diffInSeconds1 = GetTimeSync -sshKey $sshKey -ipv4 $ipv4
$msg = "ERROR : Before reboot, check time drift, Test case FAILED"
if ( -not $diffInSeconds1 )
{
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}
#
#if ($diffInSeconds -and $diffInSeconds -lt 5)
#{
#    $msg = "Time is properly synced before reboot"
#    Write-Output $msg | Tee-Object -Append -file $summaryLog
#    $retVal = $True
#}

# Source TCUtils.ps1 for test related functions
  if (Test-Path ".\setupScripts\TCUtils.ps1")
  {
    . .\setupScripts\TCUtils.ps1
  }
  else
  {
    LogMsg 0 "ERROR: Could not find setupScripts\TCUtils.ps1"
    return $False
  }

$remotefile = "auto_rdos_Reboot.sh"

#
# Start to reboot
#
LogMsg 0 "INFO : Start to reboot for ${reboot_count} times"
$retVal = RunRemoteScript1 $remotefile

$msg = "INFO : RunRemoteScript $remotefile successfully"
if (-not $retVal)
{
    $msg = "ERROR : RunRemoteScript $remotefile failed"
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

Write-Output $msg | Tee-Object -Append -file $summaryLog

#
# After reboot for many times, re-check the time sync.
# First check whether vm is running
$retVal = $False

$timeout = 100
$retVal = WaitForVMToStartSSH $ipv4 $timeout

if ( -not $retVal )
{
    Write-Output "ERROR : Wait for vm ssh failed" | Tee-Object -Append -file $summaryLog
    return $False
}
Write-Output "INFO : Wait for vm ssh successfully" | Tee-Object -Append -file $summaryLog

$diffInSeconds2 = $null
$diffInSeconds2 = GetTimeSync -sshKey $sshKey -ipv4 $ipv4
$msg = "ERROR : After reboot, check time sync, Test case FAILED"
if ( -not $diffInSeconds2 )
{
    Write-Output $msg | Tee-Object -Append -file $summaryLog
    return $False
}

$timeDrift = $diffInSeconds1 - $diffInSeconds2
$drift = [Math]::Abs($timeDrift)
Write-Output "INFO : $timeDrift = $diffInSeconds1 - $diffInSeconds2" | Tee-Object -Append -file $summaryLog
$msg = "ERROR : Time drift is lager than 5, test case is failed"
if ( $drift -and $drift -lt 5 )
{
    $msg = "INFO : Time drift is $drift, test case is passed"
    $retVal = $True
}

Write-Output $msg | Tee-Object -Append -file $summaryLog

return $retVal
