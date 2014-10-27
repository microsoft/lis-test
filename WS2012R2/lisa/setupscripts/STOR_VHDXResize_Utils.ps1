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
    Basic functions for STOR_VHDXResize TC area
.Description
    This is a PowerShell script which contains all the functions needed by
	the STOR_VHDXResize test and setup scripts 
    Functions included:
		- GetRemoteFileInfo([String] $filename, [String] $server )
		- ConvertStringToUInt64([string] $str)
		- RunTest ([String] $filename)
		- CheckResult()
		- SummaryLog()
		- RunTestLog([String] $filename, [String] $logDir, [String] $TestName)
		- MigrateVM()
#>

#######################################################################
#
# GetRemoteFileInfo()
#
# Description:
#     Use WMI to retrieve file information for a file residing on the
#     Hyper-V server.
#
# Return:
#     A FileInfo structure if the file exists, null otherwise.
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
# Convert size String
#######################################################################
function ConvertStringToUInt64([string] $str)
{
    $uint64Size = $null
    $newSize = $str
    #
    # Make sure we received a string to convert
    #
    if (-not $str)
    {
        Write-Error -Message "ConvertStringToUInt64() - input string is null" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

    if ($str.EndsWith("MB"))
    {
        $num = $str.Replace("MB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1MB
    }
    elseif ($str.EndsWith("GB"))
    {
        $num = $str.Replace("GB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1GB
    }
    elseif ($str.EndsWith("TB"))
    {
        $num = $str.Replace("TB","")
        $uint64Size = ([Convert]::ToUInt64($num)) * 1TB
    }
    else
    {
        Write-Error -Message "Invalid newSize parameter: ${str}" -Category InvalidArgument -ErrorAction SilentlyContinue
        return $null
    }

    return $uint64Size
}

#######################################################################
# Run test file inside the guest VM
#######################################################################
function RunTest ([String] $filename)
{

    "exec ./${filename}.sh &> ${filename}.log " | out-file -encoding ASCII -filepath runtest.sh

    .\bin\pscp.exe -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to copy startstress.sh to the VM" -ErrorAction SilentlyContinue
       return $False
    }

     .\bin\pscp.exe -i ssh\${sshKey} .\remote-scripts\ica\${filename}.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Error -Message "Error: Unable to copy ${filename}.sh to the VM" -ErrorAction SilentlyContinue
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${filename}.sh  2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run dos2unix on ${filename}.sh" -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Error -Message "Error: Unable to run dos2unix on runtest.sh" -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${filename}.sh   2> /dev/null"
    if (-not $?)
    {
        Write-Error -Message "Error: Unable to chmod +x ${filename}.sh" -ErrorAction SilentlyContinue
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Error -Message "Error: Unable to chmod +x runtest.sh " -ErrorAction SilentlyContinue
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh 2> /dev/null"
    if (-not $?)
    {
         Write-Error -Message "Error: Unable to run runtest.sh " -ErrorAction SilentlyContinue
        return $False
    }

    del runtest.sh
    return $True
}

#########################################################################
#    get state.txt file from VM.
########################################################################
function CheckResult()
{
    $retVal = $False
    $stateFile     = "state.txt"
	$localStateFile= "${vmName}_state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $timeout       = 6000

    "Info :   pscp -q -i ssh\${sshKey} root@${ipv4}:$stateFile} ."
    while ($timeout -ne 0 )
    {
		.\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${stateFile} ${localStateFile} #| out-null
		$sts = $?
		if ($sts)
		{
			if (test-path $localStateFile)
			{
				$contents = Get-Content -Path $localStateFile
				if ($null -ne $contents)
				{
						if ($contents -eq $TestCompleted)
						{
							# Write-Host "Info : state file contains Testcompleted"
							$retVal = $True
							break

						}

						if ($contents -eq $TestAborted)
						{
							 Write-Host "Info : State file contains TestAborted failed. "
							 break

						}

						$timeout--

						if ($timeout -eq 0)
						{
							Write-Error -Message "Error : Timed out on Test Running , Exiting test execution."   -ErrorAction SilentlyContinue
							break
						}

				}
				else
				{
					Write-Host "Warn : state file is empty"
					break
				}

			}
			else
			{
				 Write-Host "Warn : ssh reported success, but state file was not copied"
				 break
			}
		}
		else #
		{
			 Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
			 Write-Error -Message "Error : unable to pull state.txt from VM." -ErrorAction SilentlyContinue
			 break
		}
    }
    del $localStateFile
    return $retVal
}

#########################################################################
#    get summary.log file from VM.
########################################################################
function SummaryLog()
{
    $retVal = $False
    $summaryFile   = "summary.log"
    $localVMSummaryLog = "${vmName}_error_summary.log"

    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${summaryFile} ${localVMSummaryLog} #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $localVMSummaryLog)
        {
            $contents = Get-Content -Path $localVMSummaryLog
            if ($null -ne $contents)
            {
                   Write-Output "Error: ${contents}" | Tee-Object -Append -file $summaryLog
            }
            $retVal = $True
        }
        else
        {
             Write-Host "Warn : ssh reported success, but summary file was not copied"
        }
    }
    else #
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull summary.log from VM." -ErrorAction SilentlyContinue
    }
     del $summaryFile
     return $retVal
}

#########################################################################
#    get runtest.log file from VM.
########################################################################
function RunTestLog([String] $filename, [String] $logDir, [String] $TestName)
{
    $retVal = $False
    $RunTestFile   = "${filename}.log"

    .\bin\pscp.exe -q -i ssh\${sshKey} root@${ipv4}:${RunTestFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $RunTestFile)
        {
            $contents = Get-Content -Path $RunTestFile
            if ($null -ne $contents)
            {
                    move "${RunTestFile}" "${logDir}\${TestName}_${filename}_vm.log"

                   #Get-Content -Path $RunTestFile >> {$TestLogDir}\*_ps.log
                   $retVal = $True
            }
            else
            {
                Write-Host "Warn : RunTestFile is empty"
            }
        }
        else
        {
             Write-Host "Warn : ssh reported success, but RunTestFile file was not copied"
        }
    }
    else
    {
         Write-Error -Message "Error : pscp exit status = $sts" -ErrorAction SilentlyContinue
         Write-Error -Message "Error : unable to pull RunTestFile from VM." -ErrorAction SilentlyContinue
         return $False
    }
     return $retVal
}

#######################################################################
#
# MigrateVM()
#
#######################################################################
function MigrateVM()
{

    #
    # Load the cluster commandlet module
    #
    $sts = get-module | select-string -pattern FailoverClusters -quiet
    if (! $sts)
    {
        Import-module FailoverClusters
        return $False
    }

    #
    # Have migration networks been configured?
    #
    $migrationNetworks = Get-ClusterNetwork
    if (-not $migrationNetworks)
    {
        "Error: $vmName - There are no Live Migration Networks configured"
        return $False
    }

    #
    # Get the VMs current node
    #
    $vmResource =  Get-ClusterResource | where-object {$_.OwnerGroup.name -eq "$vmName" -and $_.ResourceType.Name -eq "Virtual Machine"}
    if (-not $vmResource)
    {
        "Error: $vmName - Unable to find cluster resource for current node"
        return $False
    }

    $currentNode = $vmResource.OwnerNode.Name
    if (-not $currentNode)
    {
        "Error: $vmName - Unable to set currentNode"
        return $False
    }

    #
    # Get nodes the VM can be migrated to
    #
    $clusterNodes = Get-ClusterNode
    if (-not $clusterNodes -and $clusterNodes -isnot [array])
    {
        "Error: $vmName - There is only one cluster node in the cluster."
        return $False
    }

    #
    # For the initial implementation, just pick a node that does not
    # match the current VMs node
    #
    $destinationNode = $clusterNodes[0].Name.ToLower()
    if ($currentNode -eq $clusterNodes[0].Name.ToLower())
    {
        $destinationNode = $clusterNodes[1].Name.ToLower()
    }

    if (-not $destinationNode)
    {
        "Error: $vmName - Unable to set destination node"
        return $False
    }

    "Info : Migrating VM $vmName from $currentNode to $destinationNode"

    $error.Clear()
    $sts = Move-ClusterVirtualMachineRole -name $vmName -node $destinationNode
    if ($error.Count -gt 0)
    {
        "Error: $vmName - Unable to move the VM"
        $error
        return $False
    }

}
