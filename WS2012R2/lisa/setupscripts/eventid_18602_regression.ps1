############################################################################
#
# Description:
#
#     This script will start/stop a VM as many times as specified in the
#     count parameter and check that the VM reboots successfully.
#
############################################################################
param([string] $vmName, [string] $hvServer, [string] $testParams)

function Wait-VMState {
    param(
        $VMName,
        $VMState,
        $HvServer,
        $RetryCount=30,
        $RetryInterval=5
    )

    $currentRetryCount = 0
    while ($currentRetryCount -lt $RetryCount -and `
              (Get-VM -ComputerName $hvServer -Name $vmName).State -ne $VMState) {
        Write-Output "Waiting for VM ${VMName} to enter ${VMState} state"
        Start-Sleep -Seconds $RetryInterval
        $currentRetryCount++
    }
    if ($currentRetryCount -eq $RetryCount) {
        Write-Output "VM ${VMName} failed to enter ${VMState} state"
        return $false
    }
    return $true
}

function Wait-VMHeartbeatOK {
    param(
        $VMName,
        $HvServer,
        $RetryCount=30,
        $RetryInterval=5
    )
    $currentRetryCount = 0
    do {
        $currentRetryCount++
        Start-Sleep -Seconds $RetryInterval
        Write-Output "Waiting for VM ${VMName} to enter Heartbeat OK state"
    } until ($currentRetryCount -ge $RetryCount -or `
                 (Get-VMIntegrationService -VMName $vmName -ComputerName $hvServer | `
                  Where-Object  { $_.name -eq "Heartbeat" }
              ).PrimaryStatusDescription -eq "OK")
    if ($currentRetryCount -eq $RetryCount) {
        Write-Output "VM ${VMName} failed to enter Heartbeat OK state"
        return $false
    }
    return $true
}

function Wait-VMEvent {
    param(
        $VMName,
        $StartTime,
        $EventCode,
        $HvServer,
        $RetryCount=30,
        $RetryInterval=5
    )

    $currentRetryCount = 0
    while ($currentRetryCount -lt $RetryCount) {
        Write-Output "Checking eventlog for event code $EventCode triggered by VM ${VMName}"
        $currentRetryCount++
        $events = @(Get-WinEvent -FilterHashTable `
            @{LogName = "Microsoft-Windows-Hyper-V-Worker-Admin";
              StartTime = $StartTime; ID = $EventCode} `
            -ComputerName $hvServer -ErrorAction SilentlyContinue)
        foreach ($evt in $events) {
            if ($evt.message.Contains($vmName)) {
                Write-Output "Event code $EventCode triggered by VM ${VMName}"
                Write-Output $evt.message
                return $true
            }
        }
        Start-Sleep $RetryInterval
    }
    if ($currentRetryCount -eq $RetryCount) {
        Write-Output "VM ${VMName} failed to trigger event on the host"
        return $false
    }
}

function Trigger-MultipleReboots {
    # Check parameters
    if ($vmName -eq $null) {
        "Error: VM name is null"
        return $False
    }

    if ($hvServer -eq $null) {
        "Error: hvServer is null"
        return $False
    }

    # Parse / Check test parameters
    $rootDir = $null
    $params = $testParams.Split(';')
    foreach ($p in $params) {
        if ($p.Trim().Length -eq 0) {
            continue
        }

        $tokens = $p.Trim().Split('=')

        if ($tokens.Length -ne 2) {
            "Warn : test parameter '$p' is being ignored because it appears to be malformed"
        }

        if ($tokens[0].Trim() -eq "RootDir") {
            $rootDir = $tokens[1].Trim()
        }

        if ($tokens[0].Trim() -eq "count") {
            $count = $tokens[1].Trim()
        }
    }

    if ($rootDir -eq $null) {
        "Error: The RootDir test parameter is not defined."
        return $False
    }

    # Start the actual testing
    pushd $rootDir
    $summaryLog  = "${vmName}_summary.log"
    del $summaryLog -ErrorAction SilentlyContinue

    # Check VM exists and if it is running
    $vm = Get-VM $vmName -ComputerName $hvServer
    if (-not $vm) {
        "Error: Cannot find VM ${vmName} on server ${hvServer}"
        Write-Output "VM ${vmName} not found" | Out-File -Append $summaryLog
        return $False
    }
    if ($($vm.State) -ne "Running") {
        "Error: VM ${vmName} is not in the running state" | Out-File -Append $summaryLog
        return $False
    }

    # Check VM responds to reboot via ctrl-alt-del
    Write-Output "Trying to press ctrl-alt-del from VM's keyboard."
    $VMKB = gwmi -namespace "root\virtualization\v2" -class "Msvm_Keyboard" `
                -ComputerName $hvServer -Filter "SystemName='$($vm.Id)'"
    $VMKB.TypeCtrlAltDel()
    if($? -eq "True") {
        Write-Output "VM received the ctrl-alt-del signal successfully."
    } else {
        Write-Output "VM did not receive the ctrl-alt-del signal successfully."
        return $False
    }
    $resultVMState = Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running" `
            -RetryCount 60 -RetryInterval 2
    $resultVMHeartbeat = Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer `
            -RetryCount 60 -RetryInterval 2
    if (!$resultVMState -or !$resultVMHeartbeat) {
        Write-Output "Error: Test case timed out waiting for the VM to reach Running state after receiving ctrl-alt-del."
        return $False
    }

    # Check VM can be stress rebooted
    Write-Output "Setting the boot count to 0 for rebooting the VM"
    $bootcount = 0
    $testStartTime = [DateTime]::Now

    while ($count -gt 0) {
        Start-VM -Name $VMName  -ComputerName $HvServer -Confirm:$false
        $resultVMStateOn = Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running" `
                -RetryCount 60 -RetryInterval 2
        $resultVMHeartbeat = Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer `
                -RetryCount 60 -RetryInterval 2
        Start-Sleep -S 60
        Stop-VM -Name $VMName -ComputerName $HvServer -Confirm:$false -Force
        $resultVMStateOff = Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Off" `
                -RetryCount 60 -RetryInterval 2

        if (!$resultVMStateOn -or !$resultVMHeartbeat -or !$resultVMStateOff) {
            Write-Output "Error: Test case timed out for VM to go to from Running to Off state"  | `
                Out-File -Append $summaryLog
            return $False
        }
        $resultEvent = Wait-VMEvent -VMName $vmName -HvServer $hvServer -StartTime $testStartTime `
                -EventCode 18602 -RetryCount 2 -RetryInterval 1
        if ( $resultEvent[-1] ) {
            Write-Output "Error: VM $vmName triggered a critical event 18602 on the host" | `
                Out-File -Append $summaryLog
            return $False
        }
        $count -= 1
        $bootcount += 1
        Write-Output "Boot count:"$bootcount
    }

    Write-Output "Info: VM rebooted $bootcount times successfully" | Out-File -Append $summaryLog
    Write-Output "Info: VM did not trigger a critical event 18602 on the host" | Out-File -Append $summaryLog
    return $true
}

try {
    return (Trigger-MultipleReboots)
} catch {
    Write-Output $_ | Out-File -Append $summaryLog
    return $false
}
