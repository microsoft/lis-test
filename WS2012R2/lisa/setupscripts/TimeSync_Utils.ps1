
#####################################################################
#
# AskVmForTime()
#
#####################################################################
function AskVmForTime([String] $sshKey, [String] $ipv4, [string] $command)
{
    <#
    .Synopsis
        Send a time command to a VM
    .Description
        Use SSH to request the data/time on a Linux VM.
    .Parameter sshKey
        SSH key for the VM
    .Parameter ipv4
        IPv4 address of the VM
    .Parameter command
        Linux date command to send to the VM
    .Output
        The date/time string returned from the Linux VM.
    .Example
        AskVmForTime "lisa_id_rsa.ppk" "192.168.1.101" 'date "+%m/%d/%Y%t%T%p "'
    #>

    $retVal = $null

    $sshKeyPath = Resolve-Path $sshKey
    
    #
    # Note: We did not use SendCommandToVM since it does not return
    #       the output of the command.
    #
    $dt = .\bin\plink -i ${sshKeyPath} root@${ipv4} $command
    if ($?)
    {
        $retVal = $dt
    }
    else
    {
        LogMsg 0 "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    return $retVal
}


#####################################################################
#
# GetUnixVMTime()
#
#####################################################################
function GetUnixVMTime([String] $sshKey, [String] $ipv4)
{
    <#
    .Synopsis
        Return a Linux VM current time as a string.
    .Description
        Return a Linxu VM current time as a string
    .Parameter sshKey
        SSH key used to connect to the Linux VM
    .Parameter ivp4
        IP address of the target Linux VM
    .Example
        GetUnixVMTime "lisa_id_rsa.ppk" "192.168.6.101"
    #>

    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }

    #
    # now=`date "+%m/%d/%Y/%T"
    # returns 04/27/2012/16:10:30PM
    #
    $unixTimeStr = $null
    $command = 'date "+%m/%d/%Y/%T" -u'

    $unixTimeStr = AskVMForTime ${sshKey} $ipv4 $command
    if (-not $unixTimeStr -and $unixTimeStr.Length -lt 10)
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
       "Error: Unable to get date/time string from VM"
        return $False
    }

    $pattern = 'MM/dd/yyyy/HH:mm:ss'
    $unixTime = [DateTime]::ParseExact($unixTimeStr, $pattern, $null)

    #
    # Get our time
    #
    $windowsTime = [DateTime]::Now.ToUniversalTime()

    #
    # Compute the timespan, then convert it to the absolute value of the total difference in seconds
    #
    $diffInSeconds = $null
    $timeSpan = $windowsTime - $unixTime
    if (-not $timeSpan)
    {
        "Error: Unable to compute timespan"
        return $False
    }
    else
    {
        $diffInSeconds = [Math]::Abs($timeSpan.TotalSeconds)
    }

    #
    # Display the data
    #
    "Windows time: $($windowsTime.ToString())"
    "Unix time: $($unixTime.ToString())"
    "Difference: $diffInSeconds"

     Write-Output "Time difference = ${diffInSeconds}" | Out-File -Append $summaryLog
     return $diffInSeconds
}