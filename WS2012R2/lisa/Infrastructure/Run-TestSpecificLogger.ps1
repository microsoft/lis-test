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
    Parse the network bandwidth data from the iPerf test log.

.Description
    Parse the network bandwidth data from the iPerf test log.
    
.Parameter XMLFileName
    The LISA XML file. 

.Example
    Run-TestSpecificLogger.ps1 D:\Lisa\XML\Perf_iPerf.xml

#>

param([string]$XMLFileName)

#----------------------------------------------------------------------------
# Start a new PowerShell log.
#----------------------------------------------------------------------------
Start-Transcript ".\Run-TestSpecificLogger.ps1.log" -force

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Run-TestSpecificLogger.ps1]..." -foregroundcolor cyan
Write-Host "`$XMLFileName = $XMLFileName" 

#----------------------------------------------------------------------------
# Check the parameters
#----------------------------------------------------------------------------
# check the XML file provided
if ($XMLFileName -eq $null -or $XMLFileName -eq "")
{
    Throw "Parameter XMLFileName is required."
}
else
{
    if (! (test-path $XMLFileName))
    {
        write-host -f Red "Error: XML config file '$XMLFileName' does not exist."
        Throw "Parameter XmlFilename is required."
    }
}
$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
if ($null -eq $xmlConfig)
{
    write-host -f Red "Error: Unable to parse the .xml file"
    Throw "Bad XML file"
}

$XMLFileNameWithoutExt = [io.path]::GetFileNameWithoutExtension($XMLFileName)
$testCaseName = $XMLFileNameWithoutExt
if ($testCaseName.Length -gt 50)
{
    # in database, this field only allows 50 chars
    $testCaseName = $testCaseName.Substring(0, 50)
}

# Get the Log Folder defined in the XML file
$LogFolder = $xmlConfig.config.global.logfileRootDir
if ($LogFolder -eq $null -or $LogFolder -eq "")
{
    Throw "Parameter LogFolder is required."
}
Write-Host "`$LogFolder = $LogFolder" 

#----------------------------------------------------------------------------
# Read configuration from XML file
#----------------------------------------------------------------------------
$VMName = [string]::Empty
$numberOfVMs = $xmlConfig.config.VMs.ChildNodes.Count
Write-Host "Number of VMs defined in the XML file: $numberOfVMs"
if ($numberOfVMs -eq 0)
{
    Throw "No VM is defined in the LISA XML file."
}
elseif ($numberOfVMs -gt 1)
{
    foreach($node in $xmlConfig.config.VMs.ChildNodes)
    {
        if (($node.role -eq $null) -or ($node.role.ToLower() -ne "nonsut"))
        {
            #just use the 1st SUT VM name
            $VMName = $node.vmName
            break
        }
    }
}
else
{
    $VMName = $xmlConfig.config.VMs.VM.VMName
}
if ($VMName -eq [string]::Empty)
{
    Write-Host "!!! No VM is found from the LISA XML file."
    Throw "No VM defined in the XML file"
}
Write-Host "`$VMName = $VMName" 

#----------------------------------------------------------------------------
# Check the test specific log parser
# the log parser should be Parse-Log.XMLFileName.ps1
#----------------------------------------------------------------------------
Write-Host "Current test running folder:  $($PWD.Path)"

$XMLFileNameWithoutExt = [io.path]::GetFileNameWithoutExtension($XMLFileName)
#Update - if there are more xml files defined for different test scenarios
#example: Perf_IOZone.l4u4-r32k.xml to test the scenario with 4 IOzone processes and 32KB record size.
$LogParserName = $XMLFileNameWithoutExt.split(".")[0]

$parserFileName = ".\Infrastructure\Parse-Log." + $LogParserName + ".ps1"
if (test-path($parserFileName))
{
    Write-Host "The test specific log parser is found: " $parserFileName
}
else
{
    Write-Host "The test specific log parser does not exist: " $parserFileName 
    Write-Host "Treat this as Feature test result. Parse the XML log file... "
    $parserFileName = ".\Infrastructure\Parse-Log.FeatureTest.ps1"
    if ($(test-path($parserFileName)) -eq $false)
    {
        Write-Host "The feature test log parser is not found: " $parserFileName
        Throw "No log parser found" 
    }
}

#----------------------------------------------------------------------------
# Get performance result from benchmark tool logs
#----------------------------------------------------------------------------
$dataTableName = ""
$stringFieldNames = New-Object System.Collections.Specialized.StringCollection 
$stringFieldValues = New-Object System.Collections.Specialized.StringCollection 
$nonStringFieldNames = New-Object System.Collections.Specialized.StringCollection
$nonStringFieldValues = New-Object System.Collections.Specialized.StringCollection

#source the benchmark specific log parser
#this parser should have defined the function: ParseBenchmarkLogFile
. $parserFileName

$dataTableObjs = ParseBenchmarkLogFile $LogFolder $XMLFileName
$totalReturns = $dataTableObjs.Count
Write-Host "The return values from benchmark specific log parser:"
Write-Host $dataTableObjs
$isCallPass = $dataTableObjs[$totalReturns-1]
if ($isCallPass -eq $false)
{
    Write-Host "Run benchmark specific logger failed - it returned FALSE"
    Throw "Run logger failed"   
}
else
{
    Write-Host "Run benchmark specific logger passed"
}

$dataTableName = $dataTableObjs[$totalReturns-6]
if (($dataTableName -eq $null) -or ($dataTableName -eq ""))
{
    Write-Host "The benchmark specific logger did not provide DataTable name in the first element of its return value"
    Throw "Bad logger"
}

$e1 = $dataTableObjs[$totalReturns-5]
$e2 = $dataTableObjs[$totalReturns-4]
$e3 = $dataTableObjs[$totalReturns-3]
$e4 = $dataTableObjs[$totalReturns-2]
if (($e1 -ne $null) -and ($e1.Count -ne 0))
{
    $stringFieldNames.AddRange($e1)
}
if (($e2 -ne $null) -and ($e2.Count -ne 0))
{
    $stringFieldValues.AddRange($e2)
}
if (($e3 -ne $null) -and ($e3.Count -ne 0))
{
    $nonStringFieldNames.AddRange($e3)
}
if (($e4 -ne $null) -and ($e4.Count -ne 0))
{
    $nonStringFieldValues.AddRange($e4)
}

$stringFieldNames.Add("TestDate") | Out-Null
$stringFieldNames.Add("HostOS") | Out-Null
$stringFieldNames.Add("HostName") | Out-Null
$stringFieldNames.Add("GuestOS") | Out-Null
$stringFieldNames.Add("LinuxDistro") | Out-Null
$stringFieldNames.Add("TestCaseName") | Out-Null

$date = Get-Date
$stringFieldValues.Add( $date.ToShortDateString() ) | Out-Null
$stringFieldValues.Add( (Get-WmiObject -class Win32_OperatingSystem).Caption ) | Out-Null
$stringFieldValues.Add( $env:computername.$env:userdnsdomain ) | Out-Null
$stringFieldValues.Add( "Linux" ) | Out-Null
$stringFieldValues.Add( $VMName ) | Out-Null
$stringFieldValues.Add( $testCaseName ) | Out-Null


#----------------------------------------------------------------------------
# Build sql command string and insert result into SQL database
#----------------------------------------------------------------------------
$fieldConn = "[" + $stringFieldNames[0] + "]"
for($i =1; $i -lt $stringFieldNames.Count; $i++ )
{
    $fieldConn += ",[" + $stringFieldNames[$i] + "]"
}
for($i =0; $i -lt $nonStringFieldNames.Count; $i++ )
{
    $fieldConn += ",[" + $nonStringFieldNames[$i] + "]"
}

$valueConn = "'" + $stringFieldValues[0] + "'"
for($i =1; $i -lt $stringFieldValues.Count; $i++ )
{
    $valueConn += ",'" + $stringFieldValues[$i] + "'"
}
for($i =0; $i -lt $nonStringFieldValues.Count; $i++ )
{
    $valueConn += "," + $nonStringFieldValues[$i]
}

$dataSource = "MyTestDB"
$user = "sa"
$password= "saPassword"
$database ="LisaTestResults"
#$connectionString = "Server=$dataSource;uid=$user; pwd=$password;Database=$database;Integrated Security=False;"
# the below string is compatible with Azure SQL
$connectionString = "Server=$dataSource;uid=$user; pwd=$password;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
Write-Host "ConnectionString: $connectionString"

$query = "INSERT INTO $dataTableName (" + $fieldConn + ") VALUES (" + $valueConn + ")"
Write-Host "SQL Command: $query"

$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()

$command = $connection.CreateCommand()
$command.CommandText = $query
$result = $command.executenonquery()
$connection.Close()
Write-Host "Run SQL command succeeded"

#----------------------------------------------------------------------------
# DONE
#----------------------------------------------------------------------------
Stop-Transcript
move ".\Run-TestSpecificLogger.ps1.log" $LogFolder -force
exit 0
