############################################################################
#
# MultipleReboot.ps1
#
# Description:
#     This is a PowerShell test case script that runs on the on
#     the ICA host rather than the VM.
#
#     This script will reboot a VM as many times as specified in the count parameter
#     and check that the VM reboots successfully.
#
#     The ICA scripts will always pass the vmName, hvServer, and a
#     string of testParams to the PowerShell test case script. For
#     example, if the <testParams> section was written as:
#
#         <testParams>
#             <param>TestCaseTimeout=300</param>
#         </testParams>
#
#     The string passed in the testParams variable to the PowerShell
#     test case script script would be:
#
#         "TestCaseTimeout=300"
#
#     The PowerShell test case scripts need to parse the testParam
#     string to find any parameters it needs.
#
#     All setup and cleanup scripts must return a boolean ($true or $false)
#     to indicate if the script completed successfully or not.
#
############################################################################
param([string] $vmName, [string] $hvServer, [string] $testParams)

function CheckCurrentStateFor([String] $vmName, $newState)
{
    $stateChanged = $False
    $vm = Get-VM $vmName -ComputerName $hvServer
    if ($($vm.State) -eq $newState)
    {
        $stateChanged = $True
    }

    return $stateChanged
}

#####################################################################
#
# TestPort
#
#####################################################################
function TestPort ([String] $serverName, [Int] $port=22, [Int] $to=3)
{
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
            $sts = $tcpclient.EndConnect($iar) | out-Null
            $retVal = $true
        }
        catch
        {
            # Nothing we need to do...
        }
    }
    $tcpclient.Close()

    return $retVal
}

#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $False
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $False
}

#
# Parse the testParams string
#
$rootDir = $null
$vmIPAddr = $null

$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')

    if ($tokens.Length -ne 2)
    {
	"Warn : test parameter '$p' is being ignored because it appears to be malformed"
    }

    if ($tokens[0].Trim() -eq "RootDir")
    {
        $rootDir = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "ipv4")
    {
        $vmIPAddr = $tokens[1].Trim()
    }

    if ($tokens[0].Trim() -eq "sshKey")
    {
        $sshKey = $tokens[1].Trim()
    }
    
    if ($tokens[0].Trim() -eq "count")
    {
        $count = $tokens[1].Trim()
    }
}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

if ($vmIPAddr -eq $null)
{
    "Error: The ipv4 test parameter is not defined."
    return $False
}

cd $rootDir

$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC31" | Out-File $summaryLog

$vm = Get-VM $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: Cannot find VM ${vmName} on server ${hvServer}"
    Write-Output "VM ${vmName} not found" | Out-File -Append $summaryLog
    return $False
}

if ($($vm.State) -ne "Running")
{
    "Error: VM ${vmName} is not in the running state" | Out-File -Append $summaryLog
    "     : The Invoke-Shutdown was not sent"
    return $False
}

Write-Output "Trying to reboot once using ctrl-alt-del from VM's keyboard."

$VMKB = gwmi -namespace "root\virtualization\v2" -class "Msvm_Keyboard" -ComputerName $hvServer -Filter "SystemName='$($vm.Id)'"
$VMKB.TypeCtrlAltDel()

if($? -eq "True")
{
   Write-Output "VM received the ctrl-alt-del signal successfully."
}
else
{
   Write-Output "VM did not receive the ctrl-alt-del signal successfully."
   return $False
}

$testCaseTimeout = 120

while ($testCaseTimeout -gt 0)
{
	if ( (CheckCurrentStateFor $vmName ( "Running" )))
	{
		break
	}
	Start-Sleep -seconds 2
	$testCaseTimeout -= 2
}

while ($testCaseTimeout -gt 0)
{
	if ( (TestPort $vmIPAddr) )
	{
		break
	}
	Start-Sleep -seconds 2
	$testCaseTimeout -= 2
}

if ($testCaseTimeout -eq 0)
{
	write-output "Error: Test case timed out waiting for the VM to reach Running state after rebooting with ctrl-alt-del."
	return $False
}

#
# Set the $bootcount variable and reboot the machine $count times.
#
Write-Output "setting the boot count to 0 for rebooting the VM" | Out-File  ${rootDir}\MultipleReboot.log
$bootcount = 0

while ($count -gt 0)
{
    While ( -not (TestPort $vmIPAddr) )
    {
       Start-Sleep 5
    }
    Restart-VM -VMName $vmName -ComputerName $hvServer -Force

    Start-Sleep 5

    # Set the test case time out.

    $testCaseTimeout = 120

    while ($testCaseTimeout -gt 0)
    {
        if ( (CheckCurrentStateFor $vmName ( "Running" )))
        {
            break
        }
        Start-Sleep -seconds 2
        $testCaseTimeout -= 2
    }

    if ($testCaseTimeout -eq 0)
    {
        write-output "Error: Test case timed out waiting for VM to reboot"
        return $False
    }

    #
    # During reboot wait till the TCP port 22 to be available on the VM
    #
    while ($testCaseTimeout -gt 0)
    {
        if ( (TestPort $vmIPAddr) )
        {
            break
        }
        Start-Sleep -seconds 2
        $testCaseTimeout -= 2
    }

    if ($testCaseTimeout -eq 0)
    {
        write-output "Error: Test case timed out for VM to go to Running"
        return $False
    }

    Start-Sleep -seconds 10

    $count -= 1
    $bootcount += 1
    Write-Output "Boot count:"$bootcount
    Write-Output "Boot count:"$bootcount | Out-File -Append ${rootDir}\MultipleReboot.log
}

#
# If we got here, the VM was rebooted successfully $bootcount times
#
While( -not (TestPort $vmIPAddr) )
{
    Start-Sleep 5
}

$retVal = $true
Write-Output "VM rebooted $bootcount times successfully" | Out-File -Append $summaryLog
return $retVal
