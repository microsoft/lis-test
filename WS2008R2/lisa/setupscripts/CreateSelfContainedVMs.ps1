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
    

.Description
    For a VM to be created, the VM definition in the .xml file must
   include a hardware section.  The <parentVhd> and at least one
   <nic> tag must be part of the hardware definition.  In addition,
   if you  want the VM to be created, the <create> tag must be present
   and set to the value "true".  The remaining tags are optional.

   Before creating the VM, the script will check to make sure all
   required tags are present.  It will also check the values of the
   settings.  If the exceen the HyperV's resources, a warning message
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

.Example
   Example VM definition with a hardware section:
   <vm>
       <hvServer>nmeier2</hvServer>
       <vmName>Nick1</vmName>
       <ipv4>1.2.3.4</ipv4>
       <sshKey>rhel5_id_rsa.ppk</sshKey>
       <tests>CheckLisInstall, Hearbeat</tests>
       <hardware>
           <create>true</create>
           <numCPUs>2</numCPUs>
           <memSize>1024</memSize>
           <parentVhd>D:\HyperV\ParentVHDs\Fedora13.vhd</parentVhd>
           <nic>Legacy,InternalNet</nic>
           <nic>VMBus,ExternalNet</nic>
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
    $vm = Get-VM -Name $vmName -server $hvServer 

    


    if ($vm)
    {
        write-host  "deleting the VM"
        Remove-VM -VM $vmName -server $hvServer -Force
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
function CheckRequiredParameters([System.Xml.XmlElement] $vm)
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

    if (-not $vm.hardware.parentVhd)
    {
        "Error: VM $($vm.vmName) is missing a parentVhd tag"
        return $False
    }

    if (-not $vm.hardware.DataVhd)
    {
        "Error: VM $($vm.vmName) is missing a DataVhd tag"
        return $False
    }

    if (-not $vm.hardware.nic)
    {
        "Error: VM $($vm.vmName) does not specify any networks adapters"
        return $False
    }
    
    $vmName = $vm.vmName
    $hvServer = $vm.hvServer

    #
    # If the VM already exists, delete it
    #
    $vhdDir = Get-VHDDefaultPath -server $hvServer
    $vhdName = "${vmName}.vhdx"
    $vhdFilename = Join-Path $vhdDir $vhdName

      

    DeleteVmAndVhd $vmName $hvServer $vhdFilename 
 
      

    #
    # Make sure the future boot disk .vhd file does not already exist
    #
   $fileInfo = GetRemoteFileInfo $vhdFilename -server $hvServer
   if ($fileInfo)
   {
       "Error: The bood disk .vhd file for VM ${vmName} already exists"
       "       VHD = ${vhdFilename}"
       return $False    
   }
   
 
      #
    # Make sure the parent .vhd file exists
    #
    $parentVhd = $vm.hardware.parentVhd
    if (-not ([System.IO.Path]::IsPathRooted($parentVhd)) )
    {
        $vhdDir = Get-VHDDefaultPath -server $hvServer
        $parentVhd = Join-Path $vhdDir $parentVhd
    }

    $fileInfo = GetRemoteFileInfo $parentVhd $hvServer
    if (-not $fileInfo)
    {
        "Error: The parent .vhd file ${parentVhd} does not exist for ${vmName}"
        return $False
    }
     
     
     $dataVhd = $vm.hardware.DataVhd
    if (-not ([System.IO.Path]::IsPathRooted($dataVhd)) )
    {
        $vhdDir = Get-VHDDefaultPath -server $hvServer
        $dataVhdFile = Join-Path $vhdDir $dataVhd
    }

    $fileInfo = GetRemoteFileInfo $dataVhdFile $hvServer
    if (-not $fileInfo)
    {
        "Error: The parent .vhd file ${dataVhd} does not exist for ${vmName}"
        return $False
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
            "Warn : The numCPUs for VM ${vmName} is less than 1"
            "       numCPUs has been set to 1"
            $vm.hardware.numCPUs = "1"
        }

        #
        # Use WMI to ask for the number of logical processors on the HyperV server
        #
        $processors = GWMI Win32_Processor -computer $hvServer
        if (-not $processors)
        {
            "Warn : Unable to determine the number of processors on HyperV server ${hvServer}"
            "       numCPUs has been set to 1"
            $vm.hardware.numCPUs = "1"
            
        }
        else
        {
            $CPUs = $processors.NumberOfLogicalProcessors
            
            $maxCPUs = 0
            foreach ($result in $CPUs) {$maxCPUs++}
            
            if ($maxCPUs)
            {
                if ([int]$($vm.hardware.numCPUs) -gt $maxCPUs)
                {
                    "Warn : The numCPUs for VM ${vmName} is larger than the HyperV server supports (${maxCPUs})"
                    "       numCPUs has been set to 1"
                    $vm.hardware.numCPUs = "1" 
                }
          
            }
        }
    }


    #
    # If memSize is present, make sure its value is within a valid range.
    #
    if ($vm.hardware.memSize)
    {
        #
        # Check the syntax, and convert to MB
        #
        $tokens = ($vm.hardware.memSize).Trim().Split(" ")
        if ($tokens.Length -lt 1 -or $tokens.Length -gt 2)
        {
            "Warn : Invalid <memSize> for VM"
            "       Defaulting to memSize of 512 MB"
            $xmlMemSize = "512"
        }
        else
        {
            $mbMemSize = [UInt64] 0
            $memSize = $tokens[0].Trim()
            $memSizeUnits = "MB"

            if ($tokens.Length -eq 2)
            {
                $memSizeUnits = $tokens[1].Trim().ToUpper()
                
                if ($memSizeUnits -ne "MB" -and $memSizeUnits -ne "GB")
                {
                    "Error: Invalid unit for memSize: ${memSizeUnits}"
                    "       Defaulting to MB"
                    $mbMemSize = $memSize
                }
                else
                {
                    #
                    # Convert memSize from GB to MB
                    #
                    if ($memSizeUnits -eq "GB")
                    {
                        $mbMemSize = [String] (([Uint64] $memSize) * 1024)
                    }
                }
            }
            else
            {
                #
                # Input is a single number (we hope) so assume it's MB
                #
                $mbMemSize = $memSize
            }

            $vm.hardware.memSize = $mbMemSize
        }

        #
        # Now make sure the memSize value is reasonable
        # We picked 128 MB as the lowest amount of memory we will allow
        #
        $memSize = [Uint64] $vm.hardware.memSize
        if ($memSize -lt 128)
        {
            "Warn : The memSize for VM ${vmName} is below the minimum of 128 MB"
            "       memSize set to the default value of 512 MB"
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
            if ($memSize -gt $memInMB)
            {
                "Warn : The memSize for VM ${vmName} is larger than the HyperV servers physical memory"
                "       memSize set to the default size of 512 MB"
                $vm.hardware.memSize = "512"
            }
        }
    }

    
    
    #
    # Make sure at lease one nic was specified, and then
    # check the parameters for any and all nic tags
    #
    if (-not $vm.hardware.nic)
    {
        "Error: No NICs are defined for VM ${vmName}"
        "       The VM will not be created."
        return $False
    }

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
        $availableNetworks = Get-VMSwitch -server $hvServer
        if ($availableNetworks)
        {
            foreach ($network in $availableNetworks)
            {
                $validNetworks += $network.ElementName
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
    $dataValid = @(CheckRequiredParameters $vm)
    if ($dataValid[ $dataValid.Length - 1] -eq "True")
    {
        #
        # Create the VM
        #
        Write-host "Required Parameters check done creating VM"
        
        $newVm = New-VM $vmName -server $hvServer
        if ($null -eq $newVm)
        {
            "Error: Unable to create the VM named $($vm.vmName)."
            return $false
        }
          
        #
        # Modify VMs CPU count if user specified a new value
        #
        
        if ($vm.hardware.numCPUs -and $vm.hardware.numCPUs -ne "1")
        {
            $newCpuCount =Set-VMCPUCount $newVM $($vm.hardware.numCPUs) -server $hvServer
            if ($newCpuCount -eq $null)
            {
                "Warn : failed to modify VM ${vmName} CPU count."
                "       VM CPU count left at default of 1"
            }
        }
      
        #
        # Modify the VMs memory size of the user specified a new size
        # but only if a new size is present, and it is not equal to
        # default size of 512 MB
        #
        if ($vm.hardware.memSize -and $vm.hardware.memSize -ne "512")
        {
            $newMemSize = Set-VMMemory $newVM $($vm.hardware.memSize) -server $hvServer
            if ($newMemSize -eq $null)
            {
                "Warn : Failed to set VM $($vm.vmName) memSize to $($vm.hardware.memSize)"
                "       The VMs memory was left at the default setting"
            }
        }
     
        #
        # Add a differencing boot disk to IDE 0, port 0
        # If the parentVhd is an Absolute path, it will
        # be use as is. If parentVhd is a relative path,
        # then prepent the HyperV servers default VHD
        # directory.
        #
        $vhdDir = Get-VHDDefaultPath -server $hvServer
        $vhdName = "${vmName}.vhdx"
        $vhdFilename = Join-Path $vhdDir $vhdName

        $parentVhd = $vm.hardware.parentVhd
        if (-not ([System.IO.Path]::IsPathRooted($parentVhd)))
        {
            $parentVhd = Join-Path $vhdDir $parentVhd
        }

        #
         #Create the boot .vhd
        #
        $bootVhd = Hyper-V\New-VHD -Path $vhdFilename -ParentPath $parentVhd -ComputerName $hvServer
        
       

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
        # Attach the .vhd file to the drive
        #
        $Error.Clear() 
        $dataVhd = $vm.hardware.DataVhd
        $vhdDir = Get-VHDDefaultPath -server $hvServer
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

       
        #
        # Add the NICs
        #
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
            if ($nicType -eq "Legacy")
            {
                $legacyNIC = $True
            }

            $newNic = Add-VMNic -vm $vmName -server $hvServer -Legacy:$legacyNIC -virtualSwitch $networkName -Force
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
                        $addr = Set-VMNICAddress -NIC $newNic -MAC $macAddress -server $hvServer -Force
                        if (-not $addr)
                        {
                            "Warn : Unable to set static MAC address on nic ${nic}. NIC left with dynamic MAC"
                        }
                    }
                    else
                    {
                        "Warn : Invalid mac address for nic ${nic}.  NIC left with dynamic MAC"
                    }
                }
            }

            if ($newNic)
            {
                $nicAdded = $True
            }
            else
            {
                "Warn : Unable to add legacy NIC (${nic}) to VM ${vmName}"
            }
        }

        if (-not $nicAdded)
        {
            "Error: no NICs were added to VM ${vmName}"
            "       The VM was not created"
            DeleteVmAndVhd $vmName $hvServer $vhdFilename
            return $False
        } 
        else
        {
            Write-Host "Vm Created successfully"
            $retVal = $True
        }       
    }

    #
    # If we made it here, enough things went correctly and the VM was created

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
# Load the HyperVLib version 2 module
# Note: For V2, the module can only be imported once into powershell.
#       If you import it a second time, the Hyper-V library function
#       calls fail.
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
   write-host "importing hyperv module"
   Import-module .\HyperVLibV2sp1\HyperV.psd1
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
    }
    else
    {
        "Info : The VM $($vm.vmName) does not have a hardware definition."
        "       The VM will not be created"
    }
}

exit 0
