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
.synopsis
    Collect gcov data when test is completed.

.Description
    Save the gcov data to nfs when test is completed, the saved path is:
    /mnt/gcov/${hvServer}_${vmName}_${linux_version}/${TestName}

.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the Hyper-V server hosting the test VM.

.Parameter testParams
    Test parameters are a way of passing variables into the test case script.

#>


param( [String] $vmName, [String] $hvServer, [String] $testParams )
$sshKey = $null
$ipv4 = $null
$rootDir = $null
$TestName = $null
$nfs = $null
$source_path = $null

#####################################################################
#
# Main script body
#
#####################################################################

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

#
# Parse the testParams string
#
$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim().ToLower())
    {
      "sshkey"       { $sshKey = $fields[1].Trim() }
      "ipv4"         { $ipv4 = $fields[1].Trim() }
      "rootdir"      { $rootDir = $fields[1].Trim() }
      "testname"     { $TestName = $fields[1].Trim() }
      "nfs"          { $nfs = $fields[1].Trim() }
      "source_path"  { $source_path = $fields[1].Trim() }
      default        { continue }
    }
}
#
# Change the working directory
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

. .\setupscripts\TCUtils.ps1
# check vm state is running
$vm = Get-VM -Name $vmName -ComputerName $hvServer
if (-not $vm)
{
    "Error: Can not find '$vmName'"
    return $false
}

# Get vm IP
if (-not $ipv4)
{
    $ipv4 = GetIPv4 $vmName $hvServer
    if ($ipv4)
    {
      "Info: Get ip = $ipv4"
    }
    else
    {
       "Error: Can not get ip from $vmName"
       return $false
    }
}

#
# Make sure the required testParams were found
#
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}
if (-not $TestName)
{
    "Error: TestName argument is null"
    return $False
}
if (-not $nfs)
{
    "Error: nfs argument is null"
    return $False
}
"Info: nfs = ${nfs}"
if (-not $source_path)
{
    "Error: source_path argument is null"
    return $False
}
"Info: source_path = ${source_path}"
#
# mount nfs to guest
#

$cmd = "(mount | grep /mnt) && (umount /mnt); mount ${nfs} /mnt"
$retVal = SendCommandToVM $ipv4 $sshKey "$cmd"
if (-not $retVal)
{
    "Error: Failed to exec '$cmd'."
    return $False
}

# check lcov installed
$cmd = "which lcov"
$retVal = SendCommandToVM $ipv4 $sshKey "$cmd"
if ($retVal -eq $False)
{
    "Error: Failed to exec '$cmd'."
    return $False
}

# get linux version
$cmd = "uname -r | sed s/.`$(arch)//g"
$linux_version = ""
$linux_version = bin\plink -i ssh\${sshKey} root@${ipv4} "${cmd}"
if( $linux_version )
{
    "Info: Get linux version '$linux_version'"
}
else
{
    "Warnning: Can not get linux version on $vmName through '$cmd'"
    return $False
}

# use lcov to collect gcov data
if ( $vmName.Contains($linux_version) -eq $true )
{
    $dir = ${hvServer} + "_" + ${vmName}
}
else
{
    $dir = ${hvServer} + "_" + ${vmName} + "_" + ${linux_version}
}
if (  $dir -eq $null )
{
    "Error: Can not get directory to save coverage report"
    return $false
}
$dir = $dir.ToUpper()
$gcovDir = "/mnt/GCOV/$dir"
$outfile = "$gcovDir/$TestName"
$cmd = "[[ -d $gcovDir ]] || mkdir -p $gcovDir; (lcov -c -b $source_path -o $outfile) && [[ -s $outfile ]]"
$retVal = SendCommandToVM $ipv4 $sshKey "$cmd"
if ($retVal -eq $False)
{
    "Error: Failed to exec '$cmd'."
    return $False
}
"Info: exec '$cmd'"

$cmd = "umount /mnt"
$retVal = SendCommandToVM $ipv4 $sshKey "$cmd"
if ($retVal -eq $False)
{
    "Error: Failed to exec '$cmd'."
    return $False
}
return $True
