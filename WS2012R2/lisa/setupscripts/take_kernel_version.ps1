################################################################################
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
################################################################################

################################################################################
#
#	Description
#
#	This script will find out if new kernel exists for each version of Redhat
# from RHEL6.0 to RHEL7.4.
#	This script imports the login cookies for downloading the html to get 
# the entire list of kernels. For each version of Redhat it creates a list with 
# kernels associated and stores these informations in a hash table.
#	Each version of Redhat has a latest kernel stored in a file which is compared 
# with the last added kernel in hash table.
#	For each new kernel appear there is a message send in a properties file.
#
################################################################################
################################################################################
#
# Main script body
#
################################################################################

param ([String] $LatestVersionFile)

#site security requires TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$downloadToPath = "package.html"
$remoteFileLocation = "https://access.redhat.com/downloads/content/kernel/2.6.32-642.15.1.el6/x86_64/fd431d51/package"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$content_cookies=(Get-Content -Raw .\cookies_redhat.json | ConvertFrom-Json)

#source file with latest kernels for each version 
. .\latest_versions.ps1

#add cookies for our session
foreach($cook in $content_cookies) { 
    $cookie = New-Object System.Net.Cookie 
    $cookie.Name=$cook.name
    $cookie.Domain = $cook.domain
    $cookie.Value = $cook.value
    $cookie.Expires = '1/12/2050 12:04:12 AM' 
    $session.Cookies.Add($cookie);
}

#downloading page
Write-Host "Downloading.."
$status = Invoke-WebRequest $remoteFileLocation -WebSession $session -UseBasicParsing -TimeoutSec 900 -OutFile $downloadToPath -PassThru | select StatusCode, StatusDescription
Start-Sleep 20

#check status code
if ($status.StatusCode -ne "200")
{
    Write-Host "Error Status Code: $($status.StatusCode)"
    Write-Host "Description Code: $($status.StatusDescription)"
    exit 1
}
Write-Host "Status Code: $($status.StatusCode)"
Write-Host "Description Code: $($status.StatusDescription)"

#get list of kernel version rhel
Write-Host "Generating list.."
$html = New-Object -ComObject "HTMLFile"
$source = Get-Content -Path ".\package.html" -Raw
$source = [System.Text.Encoding]::Unicode.GetBytes($source)
$html.write($source)
$content=$html.body.getElementsByTagName('select')
$content = $content[1].textContent.Split()

#generate hash table with list of kernels for each version of rhel
$hash = @{rhel74 = @(); rhel73 = @(); rhel72=@(); rhel71=@(); rhel70=@(); rhel69=@(); 
rhel68=@(); rhel67=@(); rhel66=@(); rhel65=@(); rhel64=@(); rhel63=@(); rhel62=@(); 
rhel61=@(); rhel60=@();}

foreach ($i in $content) {
	if ($i -match "3.10.0-693"){$hash.rhel74 += "$i"}
	if ($i -match "3.10.0-514"){$hash.rhel73 += "$i"}
	if ($i -match "3.10.0-327"){$hash.rhel72 += "$i"}
	if ($i -match "3.10.0-229"){$hash.rhel71 += "$i"}
	if ($i -match "3.10.0-123"){$hash.rhel70 += "$i"}
	if ($i -match "2.6.32-696"){$hash.rhel69 += "$i"}
	if ($i -match "2.6.32-642"){$hash.rhel68 += "$i"}
	if ($i -match "2.6.32-573"){$hash.rhel67 += "$i"}
	if ($i -match "2.6.32-504"){$hash.rhel66 += "$i"}
	if ($i -match "2.6.32-431"){$hash.rhel65 += "$i"}
	if ($i -match "2.6.32-358"){$hash.rhel64 += "$i"}
	if ($i -match "2.6.32-279"){$hash.rhel63 += "$i"}
	if ($i -match "2.6.32-220"){$hash.rhel62 += "$i"}
	if ($i -match "2.6.32-131"){$hash.rhel61 += "$i"}
	if ($i -match "2.6.32-71"){$hash.rhel60 += "$i"}
	}

#compare latest kernel from the hash with latest kernel saved already
if ($hash.rhel74[0] -notmatch $latest_rhel74){
    echo "New kernel RHEL74: $($hash.rhel74[0]) \n \`r`nPrevious kernel RHEL74: $latest_rhel74 \n\n \" > env.properties
    $latest_rhel74=$hash.rhel74[0] } 
if ($hash.rhel73[0] -notmatch $latest_rhel73){
    echo "New kernel RHEL73: $($hash.rhel73[0]) \n \`r`nPrevious kernel RHEL73: $latest_rhel73 \n\n \" >> env.properties
    $latest_rhel73=$hash.rhel73[0]}
if ($hash.rhel72[0] -notmatch $latest_rhel72){
    echo "New kernel RHEL72: $($hash.rhel72[0]) \n \`r`nPrevious kernel RHEL72: $latest_rhel72 \n\n \" >> env.properties
    $latest_rhel72=$hash.rhel72[0]}
if ($hash.rhel71[0] -notmatch $latest_rhel71){
    echo "New kernel RHEL71: $($hash.rhel71[0]) \n \`r`nPrevious kernel RHEL71: $latest_rhel71 \n\n \" >> env.properties
    $latest_rhel71=$hash.rhel71[0]}
if ($hash.rhel70[0] -notmatch $latest_rhel70){
    echo "New kernel RHEL70: $($hash.rhel70[0]) \n \`r`nPrevious kernel RHEL70: $latest_rhel70 \n\n \" >> env.properties
    $latest_rhel70=$hash.rhel70[0]}
if ($hash.rhel69[0] -notmatch $latest_rhel69){
    echo "New kernel RHEL69: $($hash.rhel69[0]) \n \`r`nPrevious kernel RHEL69: $latest_rhel69 \n\n \" >> env.properties
    $latest_rhel69=$hash.rhel69[0]}
if ($hash.rhel68[0] -notmatch $latest_rhel68){
    echo "New kernel RHEL68: $($hash.rhel68[0]) \n \`r`nPrevious kernel RHEL68: $latest_rhel68 \n\n \" >> env.properties
    $latest_rhel68=$hash.rhel68[0]}
if ($hash.rhel67[0] -notmatch $latest_rhel67){
    echo "New kernel RHEL67: $($hash.rhel67[0]) \n \`r`nPrevious kernel RHEL67: $latest_rhel67 \n\n \" >> env.properties
    $latest_rhel67=$hash.rhel67[0]}
if ($hash.rhel66[0] -notmatch $latest_rhel66){
    echo "New kernel RHEL66: $($hash.rhel66[0]) \n \`r`nPrevious kernel RHEL66: $latest_rhel66 \n\n \" >> env.properties
    $latest_rhel66=$hash.rhel66[0]}
if ($hash.rhel65[0] -notmatch $latest_rhel65){
    echo "New kernel RHEL65: $($hash.rhel65[0]) \n \`r`nPrevious kernel RHEL65: $latest_rhel65 \n\n \" >> env.properties
    $latest_rhel65=$hash.rhel65[0]}
if ($hash.rhel64[0] -notmatch $latest_rhel64){
    echo "New kernel RHEL64: $($hash.rhel64[0]) \n \`r`nPrevious kernel RHEL64: $latest_rhel64 \n\n \" >> env.properties
    $latest_rhel64=$hash.rhel64[0]}	
if ($hash.rhel63[0] -notmatch $latest_rhel63){
    echo "New kernel RHEL63: $($hash.rhel63[0]) \n \`r`nPrevious kernel RHEL63: $latest_rhel63 \n\n \" >> env.properties 
    $latest_rhel63=$hash.rhel63[0]}	
if ($hash.rhel62[0] -notmatch $latest_rhel62){
    echo "New kernel RHEL62: $($hash.rhel62[0]) \n \`r`nPrevious kernel RHEL62: $latest_rhel62 \n\n \" >> env.properties
    $latest_rhel62=$hash.rhel62[0]}	
if ($hash.rhel61[0] -notmatch $latest_rhel61){
    echo "New kernel RHEL61: $($hash.rhel61[0]) \n \`r`nPrevious kernel RHEL61: $latest_rhel61 \n\n \" >> env.properties
    $latest_rhel61=$hash.rhel61[0]}	
if ($hash.rhel60[0] -notmatch $latest_rhel60){
    echo "New kernel RHEL60: $($hash.rhel60[0]) \n \`r`nPrevious kernel RHEL60: $latest_rhel60 \n\n \" >> env.properties
    $latest_rhel60=$hash.rhel60[0]}
	
#overwrite latest kernel file
echo "`$latest_rhel74=`"$latest_rhel74`" `r`n`$latest_rhel73=`"$latest_rhel73`" `r`n`$latest_rhel72=`"$latest_rhel72`"
`$latest_rhel71=`"$latest_rhel71`" `r`n`$latest_rhel70=`"$latest_rhel70`" `r`n`$latest_rhel69=`"$latest_rhel69`"
`$latest_rhel68=`"$latest_rhel68`" `r`n`$latest_rhel67=`"$latest_rhel67`" `r`n`$latest_rhel66=`"$latest_rhel66`"
`$latest_rhel65=`"$latest_rhel65`" `r`n`$latest_rhel64=`"$latest_rhel64`" `r`n`$latest_rhel63=`"$latest_rhel63`"
`$latest_rhel62=`"$latest_rhel62`" `r`n`$latest_rhel61=`"$latest_rhel61`" `r`n`$latest_rhel60=`"$latest_rhel60`"" | Out-File $LatestVersionFile


Write-Host "Completed!"
return $True
