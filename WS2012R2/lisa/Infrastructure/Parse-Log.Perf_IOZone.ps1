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
    Parse the network bandwidth data from the IOZone test log.

.Description
    Parse the network bandwidth data from the IOZone test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_IOZone.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_IOZone.xml D:\Lisa\Infrastructure

#>

function ParseBenchmarkLogFile( [string]$LogFolder, [string]$XMLFileName )
{
	#----------------------------------------------------------------------------
	# The log file pattern. The log is produced by the IOZone tool
	#----------------------------------------------------------------------------
	$IOZoneLofFile = "*_IOZoneLog.log"

	#----------------------------------------------------------------------------
	# Read the IOZone log file
	#----------------------------------------------------------------------------
	$icaLogs = Get-ChildItem "$LogFolder\$IOZoneLofFile" -Recurse
	Write-Host "Number of Log files found: "
	Write-Host $icaLogs.Count

	if($icaLogs.Count -eq 0)
	{
		return $false
	}

	$Initialwrite = $null
	$Rewrite = $null
	$Read = $null
	$Reread = $null
	$Randomread = $null
	$Randomwrite = $null
	# should only have one file. but in case there are more than one files, just use the last one simply
	foreach ($logFile  in $icaLogs)
	{
		Write-Host "One log file has been found: $logFile" 
		
		#we should find the result in the last 17 lines
		#result example: 
		#"Throughput report Y-axis is type of test X-axis is number of processes"
		#"Record size = 4 Kbytes "
		#"Output is in Kbytes/sec"
		#    
		#"  Initial write "  761841.69 
		#
		#"        Rewrite "  520879.19 
		#
		#"           Read "  724325.25 
		#
		#"        Re-read "  797489.25 
		#
		#"    Random read "  656360.38 
		#
		#"   Random write " 1125040.50 
		#
		#    
		#iozone test complete.
		#
		$iTry=1
		while ($iTry -lt 18)
		{
			$line = (Get-Content $logFile)[-1* $iTry]
			Write-Host $line
			$line=$line.Trim().Replace(" ","")
			
			$iTry++
			if ($line.Trim() -eq "")
			{
				continue
			}
			elseif ( $line.Contains("Initialwrite") -eq $true )
			{
				$Initialwrite =$line.Split("`"")[2]
				continue
			}
			elseif ( $line.Contains("Rewrite") -eq $true )
			{
				$Rewrite =$line.Split("`"")[2]
				continue
			}
			elseif ( $line.Contains("Read") -eq $true )
			{
				$Read =$line.Split("`"")[2]
				continue
			}
			elseif ( $line.Contains("Re-read") -eq $true )
			{
				$Reread =$line.Split("`"")[2]
				continue
			}
			elseif ( $line.Contains("Randomread") -eq $true )
			{
				$Randomread =$line.Split("`"")[2]
				continue
			}
			elseif ( $line.Contains("Randomwrite") -eq $true )
			{
				$Randomwrite =$line.Split("`"")[2]
				continue
			}
			else
			{
				continue
			}
		}
	}
    Write-Host "Initialwrite = $Initialwrite"
    Write-Host "Rewrite      = $Rewrite"
    Write-Host "Read         = $Read"
    Write-Host "Reread       = $Reread"
    Write-Host "Randomread   = $Randomread"
    Write-Host "Randomwrite  = $Randomwrite"
    if (($Initialwrite -eq $null) -and ($Rewrite -eq $null) -and ($Read -eq $null) -and ($Reread -eq $null) -and ($Randomread -eq $null) -and ($Randomwrite -eq $null))
    {
        Write-Host "ERROR: Cannot find performance result from the log file"
        return $false
    }

	#----------------------------------------------------------------------------
	# Read test configuration from XML file
	#----------------------------------------------------------------------------
	#get IOZone parameters
	$RecordSize = ""
	$NProcLowLimit = 1
	$NProcUpperLimit = 1
	$NPosixAsyncIO = 8
	$IOZoneParams = ""
	$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
	foreach($param in $xmlConfig.config.testCases.test.testParams.ChildNodes)
	{
		$paramText = $param.InnerText
		if ($paramText.ToUpper().StartsWith("IOZONE_PARAMS="))
		{
			$IOZoneParams = $paramText.Split('=')[1]
			break
		}
	}
	if ($IOZoneParams -ne "")
	{
		$IOZoneParams = $IOZoneParams.Replace("'","")
		$listParams = $IOZoneParams.split("-")
		foreach ($p in $listParams)
		{
			if ($p.StartsWith("r"))
			{
				$RecordSize = $p.Replace("r","").Trim()
			}
			elseif ($p.StartsWith("l"))
			{
				$NProcLowLimit = $p.Replace("l","").Trim()
			}
			elseif ($p.StartsWith("u"))
			{
				$NProcUpperLimit = $p.Replace("u","").Trim()
			}
			elseif ($p.StartsWith("k"))
			{
				$NPosixAsyncIO = $p.Replace("k","").Trim()
			}
		}
	}

	Write-Host "IOZoneParams: $IOZoneParams"
	Write-Host "RecordSize: $RecordSize"
	Write-Host "NProcLowLimit: $NProcLowLimit"
	Write-Host "NProcUpperLimit: $NProcUpperLimit"
	Write-Host "NPosixAsyncIO: $NPosixAsyncIO"

    #----------------------------------------------------------------------------
    # Return to caller script
    #----------------------------------------------------------------------------
    #1st element: the DataTable Name
    $dataTableName = "LisPerfTest_IOZone"
    #2nd element: an array of datatable field names for String columns
    $stringFieldNames = New-Object System.Collections.Specialized.StringCollection 
    $stringFieldNames.Add("recordsize")
	$stringFieldNames.Add("iozoneparams")
	#3rdd element: an array of datatable values for String columns
    $stringFieldValues = New-Object System.Collections.Specialized.StringCollection
	$stringFieldValues.Add($recordsize)
	$stringFieldValues.Add($iozoneparams)
    #4th element: an array of datatable field names for Non-String columns
    $nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldNames.Add("initialwritekbsec")
    $nonStringFieldNames.Add("rewritekbsec")
    $nonStringFieldNames.Add("readkbsec")
    $nonStringFieldNames.Add("rereadkbsec")
    $nonStringFieldNames.Add("randomreadkbsec")
    $nonStringFieldNames.Add("randomwritekbsec")
    $nonStringFieldNames.Add("nproclowlimit")
    $nonStringFieldNames.Add("nprocupperlimit")
    $nonStringFieldNames.Add("nposixasyncio")
	
    #5th element: an array of datatable values for Non-String columns
    $nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection
    $nonStringFieldValues.Add($initialwrite)
    $nonStringFieldValues.Add($rewrite)
    $nonStringFieldValues.Add($read)
    $nonStringFieldValues.Add($reread)
    $nonStringFieldValues.Add($randomread)
    $nonStringFieldValues.Add($randomwrite)
    $nonStringFieldValues.Add($nproclowlimit)
    $nonStringFieldValues.Add($nprocupperlimit)
    $nonStringFieldValues.Add($nposixasyncio)

    $array = $dataTableName, $stringFieldNames, $stringFieldValues, $nonStringFieldNames, $nonStringFieldValues
    #return the results:
    $array
    return $true
}



