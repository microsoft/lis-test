<#
.SYNOPSIS
    This script fetches Azure VMs data and generates human readable HTML report of top 20 VMs.

.DESCRIPTION
    This script fetches Azure VMs data and generates human readable HTML report of top 20 VMs.

.PARAMETER -TopVMsCount
    Type: integer
    Required: Yes.

.INPUTS
    AzureSecrets.xml file. If you are running this script in Jenkins, then make sure to add a secret file with ID: Azure_Secrets_File
    If you are running the file locally, then pass secrets file path to -customSecretsFilePath parameter.

.NOTES
    Version:        1.0
    Author:         Sean Spratt <seansp@microsoft.com>
                    Shital Savekar <v-shisav@microsoft.com>
    Creation Date:  15th December 2017
    Purpose/Change: Initial script development
  
.EXAMPLE 
    .\SubscriptionUsageTopVMs.ps1 -TopVMsCount 20
#>

param
(
    [int]$TopVMsCount = 20,
    [string]$customSecretsFilePath = $null
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
if ( $customSecretsFilePath ) {
    $secretsFile = $customSecretsFilePath
    Write-Host "Using provided secrets file: $($secretsFile | Split-Path -Leaf)" 
}
if ($env:Azure_Secrets_File) {
    $secretsFile = $env:Azure_Secrets_File
    Write-Host "Using predefined secrets file: $($secretsFile | Split-Path -Leaf) in Jenkins Global Environments."	
}
if ( $secretsFile -eq $null ) {
    Write-Host "ERROR: Azure Secrets file not found in Jenkins / user not provided -customSecretsFilePath" -ForegroundColor Red -BackgroundColor Black
    exit 1
}

if ( Test-Path $secretsFile) {
    Write-Host "$($secretsFile | Split-Path -Leaf) found."
    $xmlSecrets = [xml](Get-Content $secretsFile)
    .\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath $secretsFile
    $subscriptionID = $xmlSecrets.secrets.SubscriptionID
}
else {
    Write-Host "$($secretsFile | Split-Path -Leaf) file is not added in Jenkins Global Environments OR it is not bound to 'Azure_Secrets_File' variable." -ForegroundColor Red -BackgroundColor Black
    Write-Host "Aborting." -ForegroundColor Red -BackgroundColor Black
    exit 1
}

#---------------------------------------------------------[Script Start]--------------------------------------------------------

#region HTML File structure
$htmlHeader = '
<style type="text/css">
.tm  {border-collapse:collapse;border-spacing:0;border-color:#999;}
.tm td{font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#999;color:#444;background-color:#F7FDFA;}
.tm th{font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#999;color:#fff;background-color:#26ADE4;}
.tm .tm-dk6e{font-weight:bold;color:#ffffff;text-align:center;vertical-align:top}
.tm .tm-xa7z{background-color:#ffccc9;vertical-align:top}
.tm .tm-ys9u{background-color:#b3ffd9;vertical-align:top}
.tm .tm-7k3a{background-color:#D2E4FC;font-weight:bold;text-align:center;vertical-align:top}
.tm .tm-yw4l{vertical-align:top}
.tm .tm-6k2t{background-color:#D2E4FC;vertical-align:top}
</style>
<table class="tm">
  <tr>
    <th class="tm-dk6e" colspan="9">Top 20 VMs by their Weight (Age*CoreCount)</th>
  </tr>
  <tr>
    <td class="tm-7k3a">Sr</td>
    <td class="tm-7k3a">Weight</td>
    <td class="tm-7k3a">VMName</td>
    <td class="tm-7k3a">ResourceGroup</td>
    <td class="tm-7k3a">Location</td>
    <td class="tm-7k3a">Size</td>
    <td class="tm-7k3a">VM Age</td>
    <td class="tm-7k3a">Core Count</td>
  </tr>
'

$htmlNodeGreen = 
'
  <tr>
    <td class="tm-yw4l">SR_ID</td>
    <td class="tm-yw4l">VM_WEIGHT</td>
    <td class="tm-ys9u">OFF</td>
    <td class="tm-yw4l">INSTANCE_NAME</td>
    <td class="tm-yw4l">RESOURCE_GROUP_NAME</td>
    <td class="tm-yw4l">VM_REGION</td>
    <td class="tm-yw4l">VM_SIZE</td>
    <td class="tm-yw4l">VM_AGE</td>
    <td class="tm-yw4l">VM_CORE</td>
  </tr>
'

$htmlNodeRed =
'
  <tr>
    <td class="tm-yw4l">SR_ID</td>
    <td class="tm-yw4l">VM_WEIGHT</td>
    <td class="tm-yw4l">INSTANCE_NAME</td>
    <td class="tm-yw4l">RESOURCE_GROUP_NAME</td>
    <td class="tm-yw4l">VM_REGION</td>
    <td class="tm-yw4l">VM_SIZE</td>
    <td class="tm-yw4l">VM_AGE</td>
    <td class="tm-yw4l">VM_CORE</td>
  </tr>
'

$htmlEnd = 
'
</table>
'
#endregion4

$tick = (Get-Date).Ticks
$VMAgeHTMLFile = "vmAge.html"
$cacheFilePath = "cache.results-$tick.json"

#region Get VM Weight (Age*Cores)
$then = Get-Date
$allSizes = @{}
Write-Host "Running: Get-AzureRmLocation..."
$allRegions = Get-AzureRmLocation
foreach ( $region in $allRegions ) {
    Write-Host "Running:  Get-AzureRmVMSize -Location $($region.Location)"
    $allSizes[ $region.Location ] = Get-AzureRmVMSize -Location $region.Location
}
try {
    Write-Host "Running: Get-AzureRmVM -Status"
    $allVMStatus = Get-AzureRmVM -Status
    Write-Host "Running: Get-AzureRmStorageAccount"
    $sas = Get-AzureRmStorageAccount
}
catch {
    Write-Host "Error while fetching data. Please try again."
    Set-Content -Path $VMAgeHTMLFile -Value "There was some error in fetching data from Azure today."
    exit 1
}


Write-Host "Elapsed Time: $($(Get-Date) - $then)"
$finalResults = @()
foreach ( $vm in $allVMStatus ) {
    Write-Host "[" -NoNewline -ForegroundColor White
    Write-Host "$($(Get-Date) - $then)" -NoNewline -ForegroundColor Yellow
    Write-Host "] " -NoNewline -ForegroundColor White
    $deallocated = $false
    if ( $vm.PowerState -imatch "VM deallocated" ) {
        Write-Host " [OFF] " -NoNewline -ForegroundColor Gray
        $deallocated = $true
    }
    else {
        Write-Host " [ ON] " -NoNewline -ForegroundColor Green 
    }

    Write-Host "-Name $($vm.Name) " -NoNewline
    Write-Host "-ResourceGroup $($vm.ResourceGroupName) " -NoNewline
    Write-Host "Size=" -NoNewline
    Write-Host "$($vm.HardwareProfile.VmSize)" -NoNewline -ForegroundColor Yellow

    $storageKind = "None"
    $ageDays = -1
    $idleDays = -1

    if ( $vm.StorageProfile.OsDisk.Vhd.Uri ) {
        $vhd = $vm.StorageProfile.OsDisk.Vhd.Uri
        $storageAccount = $vhd.Split("/")[2].Split(".")[0]
        $container = $vhd.Split("/")[3]
        $blob = $vhd.Split("/")[4]

        $storageKind = "blob"

        $foo = $sas | where {  $($_.StorageAccountName -eq $storageAccount) -and $($_.Location -eq $vm.Location) }
        Set-AzureRmCurrentStorageAccount -ResourceGroupName $foo.ResourceGroupName -Name $storageAccount > $null
        $blobDetails = Get-AzureStorageBlob -Container $container -Blob $blob
        $copyCompletion = $blobDetails.ICloudBlob.CopyState.CompletionTime
        $lastWriteTime = $blobDetails.LastModified
        $age = $($(get-Date) - $copyCompletion.DateTime)
        $idle = $($(Get-Date) - $lastWriteTime.DateTime)
        $ageDays = $age.Days
        $idleDays = $idle.Days
 
        Write-Host " Age = $ageDays" -NoNewline
        Write-Host " Idle = $idleDays"
    }
    else {
        $storageKind = "disk"
        Write-Host "Running:  Get-AzureRmDisk -ResourceGroupName $($vm.ResourceGroupName) -DiskName $($vm.StorageProfile.OsDisk.Name)"
        $osdisk = Get-AzureRmDisk -ResourceGroupName $vm.ResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name
        if ( $osdisk.TimeCreated ) {
            $age = $($(Get-Date) - $osDisk.TimeCreated)
            $ageDays = $($age.Days)
            Write-Host " Age = $($age.Days)"
        }
    }
    $coreCount = $allSizes[ $vm.Location ] | where { $_.Name -eq $($vm.HardwareProfile.VmSize) }
    $newEntry = @{
        Name          = $vm.Name
        resourceGroup = $vm.ResourceGroupName
        location      = $vm.Location
        coreCount     = $coreCount.NumberOfCores
        vmSize        = $($vm.HardwareProfile.VmSize)
        Age           = $ageDays
        Idle          = $idleDays
        Weight        = $($coreCount.NumberOfCores * $ageDays)
        StorageKind   = $storageKind
        Deallocated   = $deallocated
    }

    $finalResults += $newEntry
}
Write-Host "FinalResults.Count = $($finalResults.Count)"
$finalResults | ConvertTo-Json -Depth 10 | Set-Content "$cacheFilePath"
#endregion

#region Build HTML Page

$VMAges = ConvertFrom-Json -InputObject  ([string](Get-Content -Path "$cacheFilePath"))
$VMAges = $VMAges | Sort-Object -Descending Weight
$finalHTMLString = $htmlHeader
$RGLink = "https://ms.portal.azure.com/#resource/subscriptions/$subscriptionID/resourceGroups/RESOURCE_GROUP_NAME/overview"
$VMLink = "https://ms.portal.azure.com/#resource/subscriptions/$subscriptionID/resourceGroups/RESOURCE_GROUP_NAME/providers/Microsoft.Compute/virtualMachines/INSTANCE_NAME/overview"

$RGLinkHtml = '<a href="https://ms.portal.azure.com/#resource/subscriptions/' + "$subscriptionID" + '/resourceGroups/RESOURCE_GROUP_NAME/overview" target="_blank" rel="noopener">RESOURCE_GROUP_NAME</a>'
$VMLinkHtml = '<a href="https://ms.portal.azure.com/#resource/subscriptions/' + "$subscriptionID" + '/resourceGroups/RESOURCE_GROUP_NAME/providers/Microsoft.Compute/virtualMachines/INSTANCE_NAME/overview" target="_blank" rel="noopener">INSTANCE_NAME</a>'

$maxCount = $TopVMsCount
$i = 0
$counter = 0
foreach ($currentVMNode in $VMAges) {
    if ( $currentVMNode -ne $null) {
        if ( $currentVMNode.Deallocated -eq $true) {
            #Don't consider deallocated VMs in this count.
            #$currentVMHTMLNode = $htmlNodeGreen 
        }
        else {
            $i += 1
            $currentVMHTMLNode = $htmlNodeRed 
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("SR_ID", "$i")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("VM_WEIGHT", "$($currentVMNode.Weight)")
            $currentVMHTMLLink = $VMLinkHtml.Replace("RESOURCE_GROUP_NAME", "$($currentVMNode.resourceGroup)").Replace("INSTANCE_NAME", "$($currentVMNode.Name)")
            $currentRGHTMLLink = $RGLinkHtml.Replace("RESOURCE_GROUP_NAME", "$($currentVMNode.resourceGroup)")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("INSTANCE_NAME", "$currentVMHTMLLink")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("RESOURCE_GROUP_NAME", "$currentRGHTMLLink")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("VM_REGION", "$($currentVMNode.location)")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("VM_SIZE", "$($currentVMNode.vmSize)")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("VM_AGE", "$($currentVMNode.Age)")
            $currentVMHTMLNode = $currentVMHTMLNode.Replace("VM_CORE", "$($currentVMNode.coreCount)")
            $finalHTMLString += $currentVMHTMLNode 
            if ( $i -ge $maxCount) {
                break
            }           
        }
    }
}

$finalHTMLString += $htmlEnd

Set-Content -Value $finalHTMLString -Path $VMAgeHTMLFile
#endregion

#region Original HTML Table structure
<#
<style type="text/css">
.tm  {border-collapse:collapse;border-spacing:0;border-color:#999;}
.tm td{font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#999;color:#444;background-color:#F7FDFA;}
.tm th{font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#999;color:#fff;background-color:#26ADE4;}
.tm .tm-dk6e{font-weight:bold;color:#ffffff;text-align:center;vertical-align:top}
.tm .tm-xa7z{background-color:#ffccc9;vertical-align:top}
.tm .tm-ys9u{background-color:#b3ffd9;vertical-align:top}
.tm .tm-7k3a{background-color:#D2E4FC;font-weight:bold;text-align:center;vertical-align:top}
.tm .tm-yw4l{vertical-align:top}
.tm .tm-6k2t{background-color:#D2E4FC;vertical-align:top}
</style>
<table class="tm">
  <tr>
    <th class="tm-dk6e" colspan="9">Top 100 VMs by their Weigh (Age*CoreCount)</th>
  </tr>
  <tr>
    <td class="tm-7k3a">Sr</td>
    <td class="tm-7k3a">Weight</td>
    <td class="tm-7k3a">PowerStatus</td>
    <td class="tm-7k3a">VMName</td>
    <td class="tm-7k3a">ResourceGroup</td>
    <td class="tm-7k3a">Location</td>
    <td class="tm-7k3a">Size</td>
    <td class="tm-7k3a">VM Age</td>
    <td class="tm-7k3a">Core Count</td>
  </tr>
  <tr>
    <td class="tm-yw4l">1</td>
    <td class="tm-yw4l">VM_WEIGHT</td>
    <td class="tm-ys9u">POWER_STATUS_GREEN</td>
    <td class="tm-yw4l">INSTANCE_NAME</td>
    <td class="tm-yw4l">RESOURCE_GROUP_NAME</td>
    <td class="tm-yw4l">VM_REGION</td>
    <td class="tm-yw4l">VM_SIZE</td>
    <td class="tm-yw4l">VM_AGE</td>
    <td class="tm-yw4l">VM_CORE</td>
  </tr>
  <tr>
    <td class="tm-6k2t">2</td>
    <td class="tm-6k2t">VM_WEIGHT</td>
    <td class="tm-xa7z">POWER_STATUS_RED</td>
    <td class="tm-6k2t">INSTANCE_NAME</td>
    <td class="tm-6k2t">RESOURCE_GROUP_NAME</td>
    <td class="tm-6k2t">VM_REGION</td>
    <td class="tm-6k2t">VM_SIZE</td>
    <td class="tm-6k2t">VM_AGE</td>
    <td class="tm-6k2t">VM_CORE</td>
  </tr>
</table>
#>
#endregion