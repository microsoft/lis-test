########################################################################

<#
.Parameter hvServer1 
    Primary hvServer that should be used in tests 
.Parameter hvServer2
    Secondary hvServer that should be used in tests 
.Parameter Adapter
    Default adapter name to use 
.Parameter  VMname
    Empty VM that needs to run on numa node 1

.Example
    .//Configure_Numa_Rss.ps1  -PrimaryVM PERF08 -SecondaryVM PERF09 
#>

param (
    [parameter(Mandatory=$true)]
    [String] $hvServer1,
    [parameter(Mandatory=$true)]
    [String] $hvServer2,
    [parameter(Mandatory=$false)]
    [String] $Adapter = "SLOT*"
    [parameter(Mandatory=$false)]
    [String] $VMname = "dummy"
   
)
   
function Main {
              Get-WmiObject Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion | Where-Object {$_.DeviceName -like "*Mellanox*"} | Select-Object -First 1 | Format-List
              Enable-NetAdapterRss –Name "$Adapter"
              Set-NetAdapterRss –Name "$Adapter" –Profile NUMAStatic -NumaNode 0 –BaseProcessorNumber $BaseProcessorNumber –MaxProcessorNumber $MaxProcessorNumber –MaxProcessors 8 -NumberOfReceiveQueues 8
              Get-NetAdapterRss -Name "$Adapter"
              Get-VM –ComputerName $hvServer1 | Where-Object {$_.State –eq 'Running'} | Stop-VM -TurnOff
              Start-VM -Name $VMname –ComputerName $hvServer1
              $numa = ((get-counter -ListSet "Hyper-V VM Vid Partition" –ComputerName $hvServer1).PathsWithInstances | Where-Object {$_ -like "*dummy*preferred numa node index*"} | get-counter).CounterSamples.CookedValue
              if ($numa -eq 0)
              {
                Write-Host "$VMname VM from $hvServer1 runs on NUMA NODE: $numa; keeping VM up to ensure test VM starts on numa node #1"
              }
              else
              {
                Stop-VM -Name $VMname –ComputerName $hvServer1 -TurnOff
              }
              Get-VM –ComputerName $hvServer2 | Where-Object {$_.State –eq 'Running'} | Stop-VM -TurnOff 
              Start-VM -Name $VMname –ComputerName $hvServer2
              $numa = ((get-counter -ListSet "Hyper-V VM Vid Partition" –ComputerName $hvServer2).PathsWithInstances | Where-Object {$_ -like "*dummy*preferred numa node index*"} | get-counter).CounterSamples.CookedValue
              if ($numa -eq 0)
              {
                Write-Host "$VMname VM from $hvServer2 runs on NUMA NODE: $numa; keeping VM up to ensure test VM starts on numa node #1"
              }
              else
              {
                Stop-VM -Name $VMname –ComputerName $hvServer2 -TurnOff
              }
              Get-NetAdapter -Name "*SRIOV*"  | Disable-NetAdapter –Confirm:$false
              Get-NetAdapter -Name "*SRIOV*"  | Enable-NetAdapter –Confirm:$false 
}
Main
