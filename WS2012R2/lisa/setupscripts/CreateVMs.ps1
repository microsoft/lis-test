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
    Automation to create a VM based on a set of parameters.
    
.Description
    For a VM to be created, the VM definition in the .xml file must
   include a hardware section.  The <parentVhd> and at least one
   <nic> tag must be part of the hardware definition.  In addition,
   if you  want the VM to be created, the <create> tag must be present
   and set to the value "true".  The remaining tags are optional.

   Before creating the VM, the script will check to make sure all
   required tags are present. It will also check the values of the
   settings.  If the VM exceeds the HyperV's resources, a warning message
   will be displayed, and default values will override the specified
   values.

   If a VM with the same name already exists on the HyperV
   server, the VM will be deleted.

.Parameter testParams
    Tag definitions:
       <hardware>    Start of the hardware definition section.

       <create>      If the tag is defined, and has a value of "true"
                     the VM will be created.

       <numCPUs>     The number of CPUs to assign to the VM

       <memSize>     The amount of memory to allocate to the VM.
                     Memory size can be specified as MB or GB. If
                     no unit indicator is present, MB is assumed.
                        size
                        size MB
                        size GB

       <parentVhd>   The name of the .vhd file to use as the parent
                     of the VMs boot disk.  This may be a relative
                     path, or an absolute path.  If a relative path
                     is specified, the HyperV servers default path
                     for VHDs will be prepended.

       <disableDiff> When set to true, use parentVhd as the boot disk.
                     Otherwise, a differencing disk is used instead.

       <isCluster>   When set to true, the vm will be created on the cluster
                     storage. The vhd will also be copied in the cluster
                     storage. Finally, the vm will be configured for 
                     high availability

       <nic>         Defines a NIC to add to the VM. The VM must have
                     at least one <nic> tag, but multiple <nic> are
                     allowed.  The <nic> defines the NIC to add to the
                     VM as follows:
                         <nic>NIC type, Network name, MAC address</nic>
                     Where:
                         NIC type is either VMBus or Legacy
                         Network Name is the name of an existing
                                      HyperV virtual switch
                         MAC address is optional.  If present, a static
                                      MAC address will be assigned to the
                                      new NIC. Otherwise a dynamic MAC is used.

       <imageStoreDir> A directory to locate the parentVhd, can be either a UNC or local path

       <generation>  Set to 1 to create a gen 1 VM, set to 2 to create a gen 2 VM. If nothing
                     is specified, it will use gen 1.

       <secureBoot>  Define whether to enable secure boot on gen 2 VMs. Set to "true" or "false".
                     If VM is gen 1 or if not specified, this will be false.

.Example
   Example VM definition with a hardware section:
   <global>
       <imageStoreDir>\\uncpath\imageStore</imageStoreDir>
   <vm>
       <hvServer>hvServer</hvServer>
       <vmName>VMname</vmName>
       <ipv4>1.2.3.4</ipv4>
       <sshKey>pki_id_rsa.ppk</sshKey>
       <tests>CheckLisInstall, Hearbeat</tests>
       <hardware>
           <create>true</create>
           <numCPUs>2</numCPUs>
           <memSize>1024</memSize>
           <parentVhd>D:\HyperV\ParentVHDs\distro.vhd</parentVhd>
           <nic>Legacy,InternalNet</nic>
           <nic>VMBus,ExternalNet</nic>
           <generation>1</generation>
           <secureBoot>false</secureBoot>
       </hardware>
   </vm>
    
#>

param([String] $xmlFile)

#######################################################################
#
# GetRemoteFileInfo()
#
# Description:
#    Use WMI to retrieve file information for a file residing on the
#    Hyper-V server.
#
# Return:
#    A FileInfo structure if the file exists, null otherwise.
#
#######################################################################
function GetRemoteFileInfo([String] $filename, [String] $server )
{
    $fileInfo = $null

    if (-not $filename)
    {
        return $null
    }

    if (-not $server)
    {
        return $null
    }

    $remoteFilename = $filename.Replace("\", "\\")
    
    $fileInfo = Get-WmiObject -query "SELECT * FROM CIM_DataFile WHERE Name='${remoteFilename}'" -computer $server
     
    return $fileInfo
}

#######################################################################
#
# DeleteVmAndVhd()
#
# Description:
#
#######################################################################
function DeleteVmAndVhd([String] $vmName, [String] $hvServer, [String] $vhdFilename)
{
    #
    # Delete the VM - make sure it does exist
    #
    $vm = Get-VM $vmName -ComputerName $hvServer -ErrorAction SilentlyContinue

    # Delete Role from cluster if it is already present
    Get-Command "Get-ClusterResource" -ErrorAction SilentlyContinue
    if ($?){
        $group = Get-ClusterGroup -ErrorAction SilentlyContinue
        $vm_matches = $group -match $vmName
        foreach( $vm_match in $vm_matches){
            Remove-ClusterGroup -Name $vm_match.name -RemoveResources -Force
        }
    }

    if ($vm)
    {
        if (Get-VM -Name $vmName -ComputerName $hvServer |  Where { $_.State -like "Running" })
            {
                Stop-VM $vmName -ComputerName $hvServer -TurnOff
                if (-not $?) {
                    Write-Host "Error: Unable to turn off $vmName in order to remove it!"
                    return $False
                }
            }
            
        Write-Host "Cleanup: Deleting existing VM"
        Remove-VM $vmName -ComputerName $hvServer -Force
    }

    #
    # Try to delete the .vhd file if we were given a filename, and the file exists
    #
    if ($vhdFilename)
    {
        $fileInfo = GetRemoteFileInfo $vhdFilename -server $hvServer
        if ($fileInfo)
        {
            $fileInfo.Delete()  
        }
    }
}

#######################################################################
#
# CheckRequiredParameters()
#
# Description:
#    Check the XML data for the VM to make sure all required tags
#    are present. Next, check the values of the tags to make sure
#    they are valid values.
#
#######################################################################
function CheckRequiredParameters([System.Xml.XmlElement] $vm, [XML]$xmlData)
{
    #
    # Make sure the required tags are present
    #
    if (-not $vm.vmName)
    {
        "Error: VM definition is missing a vmName tag"
        return $False
    }

    if (-not $vm.hvServer)
    {
        "Error: VM $($vm.vmName) is missing a hvServer tag"
        return $False
    }
    
    $vmName = $vm.vmName
    $hvServer = $vm.hvServer

    #
    # If the VM already exists, delete it
    # If isCluster tag is set to true, make sure that a cluster is available on the server
    #
    if ( $vm.hardware.isCluster -eq "True") {
        Get-Cluster 
        if ($? -eq $False){
            "Error: Server $hvServer doesn't have a cluster set up"
            return $False  
        }
        $clusterDir = Get-ClusterSharedVolume
        $vhdDir = $clusterDir.SharedVolumeInfo.FriendlyVolumeName
    } 
    else {
        $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
    }

    $vhdName = "${vmName}.vhdx"
    $vhdFilename = "\\" + $hvServer + "\" + $vhdDir + $vhdName
    $vhdFilename = $vhdFilename.Replace(":","$")
    DeleteVmAndVhd $vmName $hvServer $vhdFilename 

    #
    # Make sure the future boot disk .vhd file does not already exist
    #
    $fileInfo = GetRemoteFileInfo $vhdFilename -server $hvServer
    if ($fileInfo)
    {
        "Error: The boot disk .vhd file for VM ${vmName} already exists"
        "       VHD = ${vhdFilename}"
        return $False
    }

    #
    # Make sure the parent .vhd file exists
    #
    if ($vm.hardware.parentVhd)
    {
        $parentVhd = $vm.hardware.parentVhd
        if (-not ([System.IO.Path]::IsPathRooted($parentVhd)) )
        {
            $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
            if ($xmlData.Config.global.imageStoreDir)
            {
                $vhdDir = $xmlData.Config.global.imageStoreDir
            }

            $parentVhd = Join-Path $vhdDir $parentVhd
        }

        $uriPath = New-Object -TypeName System.Uri -ArgumentList $parentVhd
        if ($uriPath.IsUnc)
        {
            if (-not $(Test-Path $parentVhd))
            {
                Write-Error "Remote parent vhd file ${parentVhd} does not exist."
                return $False
            }
        } 
        else
        {
            $fileInfo = GetRemoteFileInfo $parentVhd $hvServer
            if (-not $fileInfo)
            {
                Write-Error "Error: The parent .vhd file ${parentVhd} does not exist for ${vmName}"
                return $False
            }
        }
    }
    elseif ($vm.hardware.importVM)
    {
        #
        # Verify the .xml file for the import VM exists
        #
        $importVmInfo = GetRemoteFileInfo $vm.hardware.importVM
        if (-not $fileInfo)
        {
            Write-Error "Error: The importVM xml file does not exist, or cannot be accessed"
            return $False
        }
    }
     
    $dataVhd = $vm.hardware.DataVhd
    if ($dataVhd)
    {
        if (-not ([System.IO.Path]::IsPathRooted($dataVhd)) )
        {
            $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
            $dataVhdFile = Join-Path $vhdDir $dataVhd
        }

        $fileInfo = GetRemoteFileInfo $dataVhdFile $hvServer
        if (-not $fileInfo)
        {
            Write-Error "Error: The parent .vhd file ${dataVhd} does not exist for ${vmName}"
            return $False
        }
    }

    #
    # Now check the optional parameters
    #

    #
    # If numCPUs is present, make sure its value is within a valid range.
    #
    if ($vm.hardware.numCPUs)
    {
        if ([int]$($vm.hardware.numCPUs) -lt 1)
        {
            Write-Warning "Warn : The numCPUs for VM ${vmName} is less than 1. numCPUs has been set to 1"
            $vm.hardware.numCPUs = "1"
        }

        #
        # Use WMI to ask for the number of logical processors on the HyperV server
        #
        $processors = GWMI Win32_Processor -computer $hvServer
        if (-not $processors)
        {
            Write-Warning "Warn : Unable to determine the number of processors on HyperV server ${hvServer}. numCPUs has been set to 1"
            $vm.hardware.numCPUs = "1"
            
        }
        else
        {
            $CPUs = $processors.NumberOfLogicalProcessors
            
            $maxCPUs = 0
            foreach ($result in $CPUs) {$maxCPUs += $result}
            
            if ($maxCPUs -and [int]$($vm.hardware.numCPUs) -gt $maxCPUs)
            {
                Write-Warning "Warn : The numCPUs for VM ${vmName} is larger than the HyperV server supports (${maxCPUs}). numCPUs has been set to max"
                $vm.hardware.numCPUs = $maxCPUs
            }
        }
    }

    #
    # If memSize is present, make sure it is within a valid range, then convert
    # it to MB.  If a unit specifier is not present, assume MB. Only MB and GB
    # are supported.  Strings can be in any of the following formats:
    #        "2048"
    #        "2048MB"       "2048GB"
    #        "2040 MB"      "2048 GB"
    #
    if ($vm.hardware.memSize)
    {
        #
        #    Use regular expressions to parse the memory size string
        #    and convert the value to MB.  Whitespace is parsed out.
        #
        $regex = [regex] '^(\d+)\s*([MG]B)?$'

        $memStr = $vm.hardware.memSize.Trim().ToUpper()
        $mbMemSize = "1024"

        if ( "$memStr" -match "$regex" )
        {
            switch ($matches.Count)
            {
            2   {   $mbMemSize = $matches[1] }
            3   {   $mbMemSize = $matches[1]
                    if ($matches[2] -eq "GB" ) {
                        $mbMemSize = ([uint64] $matches[1]) * 1KB
                    }
                }
            default {
                    Write-Warning "Invalid memSize. MemSize defaulting to 1024MB"
                } 
            }
        }
        else
        {
            Write-Warning "Warn: Invalid memSize. MemSize defaulting to 1024 MB"
        }

        $vm.hardware.memSize = $mbMemSize

        #
        # Make sure the memSize value is reasonable for the host.
        # We picked 512 MB as the lowest amount of memory we will allow.
        #
        $memSize = [Uint64] $vm.hardware.memSize
        if ($memSize -lt 512)
        {
            Write-Warning "The memSize for VM ${vmName} is below the minimum of 512 MB. memSize set to the default value of 512 MB"
            $vm.hardware.memSize = "512"
        }

        $physMem = GWMI Win32_PhysicalMemory -computer $hvServer
        if ($physMem)
        {
            #
            # Make sure requested memory does not exceed the HyperV servers max
            #
            $totalMemory = [Uint64] 0
            foreach($slot in $physMem)
            {
                $totalMemory += $slot.Capacity
            }
            
            $memInMB = $totalMemory / 1MB
            $mbMemSize = [uint64]$mbMemSize
            if ($mbMemSize -gt $memInMB)
            {
                Write-Warning "Warn : The memSize for VM ${vmName} is larger than the HyperV servers physical memory. memSize set to the default size of 512 MB"
                $vm.hardware.memSize = "512"
            }
        }
    }

    $validNicFound = $true
    if ($vm.hardware.nic)
    {
        $validNicFound = $false
        foreach($nic in $vm.hardware.nic)
        {
            #
            # Make sure there are three parameters specified
            #
            $tokens = $nic.Trim().Split(",")
            if (-not $tokens -or $tokens.Length -lt 2 -or $tokens.Length -gt 3)
            {
                "Error: Invalid NIC defnintion for VM ${vmName}: $nic"
                "       Syntax is 'nic type, network name', 'MAC address'"
                "       Valid nic types: Legacy, VMBus"
                "       The network name must be a valid switch name on the HyperV server"
                "       MAC address is optional.  If present, it is the 12 hex digit"
                "       MAC address to assign to the new NIC. If missing, a dynamic MAC"
                "       address will be assigned to the NIC."
                "       The NIC was not added to the VM"
                Continue
            }

            #
            # Extract the three NIC parameters
            #
            $nicType     = $tokens[0].Trim()
            $networkName = $tokens[1].Trim()

            #
            # Was a valid adapter type specified
            #
            if (@("Legacy", "VMBus") -notcontains $nicType)
            {
                "Error: Unknown NIC adapter type: ${adapterType}"
                "       The value must be one of: Legacy, VMBus"
                "       The NIC will not be added to the VM"
                Continue
            }

            #
            # Does the specified network name exist on the HyperV server
            #
            $validNetworks = @()
            $availableNetworks = Get-VMSwitch -ComputerName $hvServer
            if ($availableNetworks)
            {
                foreach ($network in $availableNetworks)
                {
                    $validNetworks += $network.Name
                }
            }
            else
            {
                "Error: Unable to determine available networks on HyperV server ${hvServer}"
                "       The NIC will not be added (${nic})"
                Continue
            }

            #
            # Is the network name known on the HyperV server
            #
            if ($validNetworks -notcontains $networkName)
            {
                "Error: The network name ${$networkName} is unknown on HyperV server ${hvServer}"
                "       The NIC will not be added to the VM"
                Continue
            }

            $macAddress  = $null
            if ($tokens.Length -eq 3)
            {
                #
                # Strip out any colons, hyphens, other junk and leave only hex digits
                #
                $macAddress = $tokens[2].Trim().ToLower() -replace '[^a-f0-9]',''

                #
                # If 12 hex digits long, it's a valid MAC address
                #
                if ($macAddress.Length -ne 12)
                {
                    "Error: The MAC address ${macAddress} has an invalid length"
                    Continue
                }
            }

            $validNicFound = $True
        }
    }
    #
    # If we got here, our final status depends on whether a valid NIC was found
    #
    return $validNicFound
}

#######################################################################
#
# CreateVM()
#
# Description:
#
#######################################################################
function CreateVM([System.Xml.XmlElement] $vm, [XML] $xmlData)
{
    $retVal = $False

    $vmName = $vm.vmName
    $hvServer = $vm.hvServer
    $vhdFilename = $null

    if (-not $vm.hardware.create -or $vm.hardware.create -ne "true")
    {
        #
        # The create attribute is missing, or it is not true.
        # So, nothing to do
        "Info : VM ${vmName} does not have a create attribute,"
        "       or the create attribute is not set to True"
        "       The VM will not be created"
        return $True
    }

    #
    # Check the parameters from the .xml file to make sure they are
    # present and valid
    #
    # Use the @() operator to force the return value to be an array
    $dataValid = @(CheckRequiredParameters $vm $xmlData)
    if ($dataValid[ $dataValid.Length - 1] -eq "True")
    {
        #
        # Create the VM
        #
        Write-host "Required parameters check done, creating VM..."
        
        $vmGeneration = 1
        if ($vm.hardware.generation) {
            $vmGeneration = [int16]$vm.hardware.generation
        }

        if ( $vm.hardware.isCluster -eq "True") {
            $clusterDir = Get-ClusterSharedVolume
            $vmDir = $clusterDir.SharedVolumeInfo.FriendlyVolumeName
        }

        # WS 2012, 2008 R2 do not support generation 2 VMs
        $OSInfo = get-wmiobject Win32_OperatingSystem -computerName $vm.hvServer
        if ( ($OSInfo.Caption -match '.2008 R2.') -or 
             ($OSInfo.Caption -match '.2012 [^R2].')
             )
            {
                if ( $vm.hardware.isCluster -eq "True") {
                    $newVm = New-VM -Name $vmName -ComputerName $hvServer -Path $vmDir
                }
                else {
                    $newVm = New-VM -Name $vmName -ComputerName $hvServer
                }
            }
        else
            {
                if ( $vm.hardware.isCluster -eq "True") {
                    $newVm = New-VM -Name $vmName -ComputerName $hvServer -Generation $vmGeneration -Path $vmDir
                }
                else {
                    $newVm = New-VM -Name $vmName -ComputerName $hvServer -Generation $vmGeneration
                }
                # Enable Guest integration services - not enabled by default
                Enable-VMIntegrationService -Name "Guest Service Interface" -vmName $vmName -ComputerName $hvServer
            }
            
        if ($null -eq $newVm) {
            Write-Error "Error: Unable to create the VM named $($vm.vmName)."
            return $false
        }

        #
        # Disable secure boot on VM unless explicitly told to enable it on Gen2 VMs
        #
        if (($newVM.Generation -eq 2)) {
            if ($vm.hardware.secureBoot -eq "true")
            {
                Set-VMFirmware -VM $newVm -EnableSecureBoot On
            }
            else
            {
                Set-VMFirmware -VM $newVm -EnableSecureBoot Off
            }
        }
          
        #
        # Modify VMs CPU count if user specified a new value
        #
        if ($vm.hardware.numCPUs -and $vm.hardware.numCPUs -ne "1")
        {
            Set-VMProcessor -VMName $vmName -Count $($vm.hardware.numCPUs) -ComputerName $hvServer
        }
      
        #
        # Modify the VMs memory size of the user specified a new size
        # but only if a new size is present, and it is not equal to
        # default size of 512 MB
        #
        if ($vm.hardware.memSize -and $vm.hardware.memSize -ne "512")
        {
            $memSize = [Uint64]$vm.hardware.memsize
            Set-VMMemory -VMName $vmName -StartupBytes $($memSize * 1MB) -ComputerName $hvServer
        }

        $parentVhd = $vm.hardware.parentVhd
        if (-not ([System.IO.Path]::IsPathRooted($parentVhd)))
        {
            $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
            if ($xmlData.Config.global.imageStoreDir)
            {
                $vhdDir = $xmlData.Config.global.imageStoreDir
            }

            # If no specific VHD file is specified, then we either find the latest image as described by a metadata file
            # Or we find the last written file
            if (!$parentVhd)
            {
                $latestFile = Join-Path $vhdDir "latest"
                if (Test-Path $latestFile)
                {
                    $parentVhd = Get-Content $latestFile
                }
                else
                {
                    $parentVhd = $(Get-ChildItem $vhdDir | Where-Object { $_.Extension -eq ".vhd" -or $_.Extension -eq ".vhdx"} | Sort LastWriteTime | Select -Last 1).Name
                }
            }

            $parentVhd = Join-Path $vhdDir $parentVhd
        }

            # If parent VHD is remote, copy it to local VHD directory
        $uriPath = New-Object -TypeName System.Uri -ArgumentList $parentVhd
        if ($uriPath.IsUnc)
        {
            $extension = (Get-Item "${parentVhd}").Extension
            if ( $vm.hardware.isCluster -eq "True") {
                $clusterDir = Get-ClusterSharedVolume
                $vhdDir = $clusterDir.SharedVolumeInfo.FriendlyVolumeName
            }else {
                if($xmlData.Config.global.VhdPath){
                    $vhdDir = $xmlData.Config.global.VhdPath
                    if ( -not (Test-Path $vhdDir)){
                        Write-host -f red "Error: Path $vhdDir given as parameter does not exist"
                        return $false
                    }
                }
                else{
                    $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
                }
            }
            # If the path has the ending backslash, remove it
            if($vhdDir.EndsWith("\")) {
                $vhdDir = $vhdDir.Substring(0,$vhdDir.Length -1)
            }
            $dstPath = $vhdDir + "\" + "${vmName}${extension}"
            $dstDrive = $dstPath.Substring(0,1)
            $dstlocalPath = $dstPath.Substring(3)
            $dstPathNetwork = "\\${hvServer}\${dstDrive}$\${dstlocalPath}"
            Write-Host "Copying parent vhd from $parentVhd to $dstPathNetwork"
            Copy-Item -Path $parentVhd -Destination $dstPathNetwork -Force
            $parentVhd = $dstPath
        }
        $vhdFilename = $parentVhd

        $disableDiff = $vm.hardware.disableDiff -eq "true"
        if (-not $disableDiff)
        {
            #
            # Create differencing boot disk.
            # If the parentVhd is an Absolute path, it will be use as is. 
            # If parentVhd is a relative path, then prepent the HyperV servers default VHD directory.
            #
            $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
            $vhdName = "${vmName}_diff.vhdx"
            $vhdFilename = $vhdDir + $vhdName
            $vhdFilenameNetPath = "\\" + $hvServer + "\" + $vhdFilename.Replace(":","$")

            # Check if differencing boot disk exists, and if yes, delete it
            if(Test-Path $vhdFilenameNetPath) {
                Remove-Item -Path $vhdFilenameNetPath -Force
            }
            #
            #Create the boot .vhd
            #
            $bootVhd = New-VHD -Path $vhdFilename -ParentPath $parentVhd -ComputerName $hvServer

            if (-not $bootVhd)
            {
                "Error: Failed to create $vhdFilename using parent $parentVhd for VM ${vmName}"
                $fileInfo = GetRemoteFileInfo $vhdFilename $hvServer
                if ($fileInfo)
                {
                    "Error: The file already exists"
                }
    
                DeleteVmAndVhd $vmName $hvServer $null
                return $false
            }
        }
       
        #
        # Add a drive to IDE 0, port 0
        #
        $Error.Clear() 
        Add-VMHardDiskDrive $vmName -Path $vhdFilename -ControllerNumber 0 -ControllerLocation 0 -ComputerName $hvServer 
        #$newDrive = Add-VMDrive $vmName -path $vhdFilename -ControllerID 0  -LUN 0 -server $hvServer 

        if ($Error.Count -gt 0)
        {
            "Error: Failed to add hard drive to IDE 0, port 0"
            #
            # We cannot create the boot disk, so delete the VM
            #
            Write-Host "VM hard disk not created"
            DeleteVmAndVhd $vmName $hvServer $vhdFilename
            return $false
        }

        #
        # If a data disk was specified...
        #
        $Error.Clear() 

        $dataVhd = $vm.hardware.DataVhd
        if ($dataVhd)
        {
            $vhdDir = $(Get-VMHost -ComputerName $hvServer).VirtualHardDiskPath
            $dataVhdFile = Join-Path $vhdDir $dataVhd
       
            Add-VMHardDiskDrive $vmName -Path $dataVhdFile -ControllerNumber 0 -ControllerLocation 1 -ComputerName $hvServer
       
            if ($Error.Count -gt 0)
            {
                "Error: Failed to attach .vhd file '$vhdFilename' to VM ${vmName}"
                #
                # We cannot create the boot disk, so delete the VM
                #
                  Write-Host "Count not to attache data disk"
                  DeleteVmAndVhd $vmName $hvServer $vhdFilename
                return $false
            }
        }

        #
        # Clear all NICs and then add the specified NICs
        #
        Get-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer | Remove-VMNetworkAdapter
        if ($vm.hardware.nic)
        {
            $nicAdded = $False
            foreach($nic in $vm.hardware.nic)
            {
                #
                # Retrieve the NIC parameters
                #
                $tokens = $nic.Trim().Split(",")
                if (-not $tokens -or $tokens.Length -lt 2 -or $tokens.Length -gt 3)
                {
                    "Error: Invalid NIC defnintion for VM ${vmName}: $nic"
                    "       The NIC was not added to the VM"
                    Continue
                }

                #
                # Extract NIC type and Network name (virtual switch name) then add the NIC
                #
                $nicType     = $tokens[0].Trim()
                $networkName = $tokens[1].Trim()

                $legacyNIC = $False
                if ($newVm.Generation -eq 1 -and $nicType -eq "Legacy")
                {
                    $legacyNIC = $True
                }

                $newNic = Add-VMNetworkAdapter -VMName $vmName -ComputerName $hvServer -IsLegacy:$legacyNIC -SwitchName $networkName -Passthru
                if ($newNic)
                {
                    #
                    # If the optional MAC address is present, set a static MAC address
                    #
                    if ($tokens.Length -eq 3)
                    {
                        $macAddress = $tokens[2].Trim().ToLower() -replace '[^a-f0-9]',''  # Leave just hex digits

                        if ($macAddress.Length -eq 12)
                        {
                            Set-VMNetworkAdapter -VMNetworkAdapter $newNic -StaticMAC $macAddress
                        }
                        else
                        {
                            Write-Warning "Warn : Invalid MAC address for NIC ${nic}. NIC left with dynamic MAC"
                        }
                    }
                }

                if ($newNic)
                {
                    $nicAdded = $True
                }
                else
                {
                    Write-Warning "Warn : Unable to add legacy NIC (${nic}) to VM ${vmName}"
                }
            }

            if (-not $nicAdded)
            {
                Write-Error "Error: no NICs were added to VM ${vmName}. The VM was not created"
                DeleteVmAndVhd $vmName $hvServer $vhdFilename
                return $False
            } 
        }
        
        #
        # Configure VM for High Availability
        #
        if( $vm.hardware.isCluster -eq "True"){
            Add-ClusterVirtualMachineRole -VirtualMachine $vmName
            if ($? -eq $False)
            {
                Write-Error "Error: High Availability configure for ${vmName} failed. The VM was not created"
                DeleteVmAndVhd $vmName $hvServer $vhdFilename
                return $False
            }
        }
        
        Write-Host "Info: VM created successfully"
        $retVal = $True       
    }

    #
    # If we made it here, enough things went correctly and the VM was created
    #
    return $retVal
}

#######################################################################
#
# Main script body
#
#######################################################################
$exitStatus = 1

if (! $xmlFile)
{
    "Error: The xmlFile argument is null."
    "False"
    exit $exitStatus
}

if (! (test-path $xmlFile))
{
    "Error: The XML file '${xmlFile}' does not exist."
    "False"
    exit $exitStatus
}

#
# Parse the .xml file
#
$xmlData = [xml] (Get-Content -Path $xmlFile)
if ($null -eq $xmlData)
{
    "Error: Unable to parse the .xml file ${xmlFile}"
    "False"
    exit $exitStatus
}

#
# Make sure at lease one VM is defined in the .xml file
#
if (-not $xmlData.Config.VMs.VM)
{
    "Error: No VMs defined in .xml file ${xmlFile}"
    "False"
    exit $exitStatus
}

#
# Process each VM definition
#
foreach ($vm in $xmlData.Config.VMs.VM)
{
    #
    # The VM needs a hardware definition before we can create it
    #
    if ($vm.hardware)
    {
        write-host "Creating VM"
        $vmCreateStatus = CreateVM $vm $xmlData

        if (-not $vmCreateStatus)
        {
            exit $exitStatus
        }
    }
    else
    {
        "Info : The VM $($vm.vmName) does not have a hardware definition."
        "       The VM will not be created"
    }
}

exit 0
