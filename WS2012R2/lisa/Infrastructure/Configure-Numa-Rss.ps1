########################################################################

<#
.Parameter hvServer1 
    Primary hvServer that should be used in tests
.Parameter hvServer2
    Secondary hvServer that should be used in tests
.Parameter Adapter
    Default adapter name to use
.Parameter  DependencyVM
    Empty VM that needs to run on numa node 1

.Example
    ./Configure-Numa-Rss.ps1 -testParams "hvServer1=LIS-PERF08,hvServer2=LIS-PERF08"
#>

param (
    [String] $testParams
)

#defined variables used
$Adapter = "SLOT*"
$DependencyVM = "dummy"
$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "hvServer1" { $hvServer1 = $fields[1].Trim() }
        "hvServer2" { $hvServer2 = $fields[1].Trim() }
        "DependencyVM" { $DependencyVM = $fields[1].Trim() }
        "Adapter" { $Adapter = $fields[1].Trim() }
        default {}
    }
}

# Display Mellanox NIC information
Get-WmiObject Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion | `
    Where-Object {$_.DeviceName -like "*Mellanox*"} | Select-Object -First 1 | Format-List

# Enable CPU specific optimizations HvServer1
Enable-NetAdapterRss -Name "$Adapter"
Set-NetAdapterRss -Name "$Adapter"  -Profile NUMAStatic -NumaNode 0 -BaseProcessorNumber 0 `
    -MaxProcessorNumber 7 -MaxProcessors 8 -NumberOfReceiveQueues 8

# Stopping all VMs to prepare test environment
Get-VM -ComputerName $hvServer1 | Where-Object {$_.State -eq "Running"} | Stop-VM -TurnOff

# Configure hvServer1
Start-VM -Name $DependencyVM -ComputerName $hvServer1

$numa = ((get-counter -ListSet "Hyper-V VM Vid Partition" -ComputerName $hvServer1).PathsWithInstances | `
        Where-Object {$_ -like "*dummy*preferred numa node index*"} | get-counter).CounterSamples.CookedValue
if ($numa -eq 0) {
    Write-Host "$DependencyVM VM from $hvServer1 runs on NUMA NODE: $numa; keeping VM up to ensure test VM starts on NUMA node #1"
}
else {
    Write-Host "$DependencyVM VM from $hvServer1 runs on NUMA NODE: $numa; stopping dependency VM"
    Stop-VM -Name $DependencyVM -ComputerName $hvServer1 -TurnOff
}
# Enable CPU specific optimizations HvServer2
Invoke-Command  -ComputerName $hvServer2 -ScriptBlock {Enable-NetAdapterRss -Name "$using:Adapter"}
Invoke-Command  -ComputerName $hvServer2 -ScriptBlock {Set-NetAdapterRss -Name "$using:Adapter"  -Profile NUMAStatic -NumaNode 0 -BaseProcessorNumber 0 `
        -MaxProcessorNumber 7 -MaxProcessors 8 -NumberOfReceiveQueues 8}

# Stopping all VMs to prepare test environment
Get-VM -ComputerName $hvServer2 | Where-Object {$_.State -eq "Running"} | Stop-VM -TurnOff

# Configure hvServer2
Start-VM -Name $DependencyVM -ComputerName $hvServer2

$numa2 = Invoke-Command  -ComputerName $hvServer2 -ScriptBlock {((get-counter -ListSet "Hyper-V VM Vid Partition" -ComputerName $using:hvServer2).PathsWithInstances | `
        Where-Object {$_ -like "*dummy*preferred numa node index*"} | get-counter).CounterSamples.CookedValue }
if ($numa2 -eq 0) {
    Write-Host "$DependencyVM VM from $hvServer2 runs on NUMA NODE: $numa2; keeping VM up to ensure test VM starts on NUMA node #1"
}
else {
    Write-Host "$DependencyVM VM from $hvServer2 runs on NUMA NODE: $numa2; stopping dependency VM"
    Stop-VM -Name $DependencyVM -ComputerName $hvServer2 -TurnOff
}

Get-NetAdapter -Name "*SRIOV*"  | Disable-NetAdapter -Confirm:$false
Get-NetAdapter -Name "*SRIOV*"  | Enable-NetAdapter  -Confirm:$false
Write-Host "NUMA configured successfully on both servers"
return $true