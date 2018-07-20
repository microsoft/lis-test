############################################################################
#
# This script prepares a Windows Server host for on-premise Hyper-V testing. 
# - downloads and installs JAVA, Git, Python 
# - sets firewall 
# - adds domain users and domain name given as parameter
# - joins the computer and users to the domain
# - creates and configures private, internal and external switches
#
# How to run:
#		.\config_server.ps1 
#
# -DomainName and -DomainUser are optional parameters
#
############################################################################

param(
[String] $DomainName,
[String] $DomainUser,
[parameter(Mandatory=$true)]
[String[]] $UsersList,
[String[]]$Roles = @("Failover-Clustering","Windows-Server-Backup","RSAT-Clustering"),
# Java Version 8 Updated 171
[String] $JavaURL = "http://javadl.oracle.com/webapps/download/AutoDL?BundleId=233172_512cd62ec5174c3487ac17c61aaa89e8",
[String] $GitURL = "https://github.com/git-for-windows/git/releases/download/v2.18.0.windows.1/Git-2.18.0-64-bit.exe",
[String] $PythonURL = "https://www.python.org/ftp/python/2.7.14/python-2.7.14.amd64.msi"
)

Set-Location "C:\Windows\Temp"
$statefile = Get-ChildItem | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq "statefile" }
if ($statefile -eq $null) {
	echo $statefile > statefile.txt

	Write-Host "Installing Windows Features"
	Install-WindowsFeature -Name $Roles -IncludeAllSubFeature -IncludeManagementTools

	$javaVersion = (Get-WmiObject Win32_Product | Where {$_.Name -match "Java"}).Version
	if (!$javaVersion) {
		Write-Host "Downloading JAVA..."
		(New-Object System.Net.WebClient).DownloadFile($JavaURL, "C:\Windows\temp\java.exe")
		Write-Host "Installing JAVA"
		Start-Process -FilePath  "C:\Windows\temp\java.exe" -Wait -ArgumentList "/s"
		$javaVersion = (Get-WmiObject Win32_Product | Where {$_.Name -match "Java"}).Version
		$env:Path += ";C:\Program Files\Java\jre1.8.0_151\bin"
		Write-Host "Java Path: $env:Path"
	}
	else {
		Write-Host "Java is already installed"
	}
	if ($javaVersion) {
		Write-Host "Java installed with success"
	}
	else {
		Write-Error "Java could not be installed"
	}

	$gitDir =  Test-Path 'C:\Program Files\Git\'
	if ($gitDir -eq $False) {
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		Write-Host "Downloading GIT..."
		(New-Object System.Net.WebClient).DownloadFile($GitURL,"C:\Windows\Temp\git.exe")
		Write-Host "Installing GIT"
		C:\Windows\Temp\git.exe /VERYSILENT
		Start-Sleep -Seconds 10
		$env:Path += ";C:\Program Files\Git\bin\"
		Write-Host "Git Path: $env:Path"
	}
	else {
		Write-Host "Git is already installed"
	}
	$gitDir = Test-Path 'C:\Program Files\Git\'
	if ($gitDir -ne $True) { 
		Write-Error "Git could not be installed"
	}
	else {
		Write-Host "Git installed with success"
	}

	$pythonRegistry = Test-Path 'C:\Python27'
	if ($pythonRegistry -eq $False) {
		Write-Host "Downloading PYTHON..."
		(New-Object System.Net.WebClient).DownloadFile($PythonURL,"C:\Windows\Temp\python.msi")
		start-sleep -Seconds 3
		Write-Host "Installing Python"
		Start-Job {C:\Windows\Temp\python.msi /QUIET}
		Start-Sleep -Seconds 10
		Write-Host "Installing deps for Python"
		$env:Path += ";C:\Python27;C:\Python27\Scripts"
		Write-Host "Python Path: $env:Path"
		Start-Sleep -Seconds 2
		python -m ensurepip
		python -m pip install --upgrade --force-reinstall pip pyodbc<=3.0.10 envparse<=0.2.0
	}
	else {
		Write-Host "Python is already installed"	
	}
	$pythonRegistry = Test-Path 'C:\Python27'
	if ($pythonRegistry -ne $True) { 
		Write-Error "Python could not be installed"
	}
	else {
		Write-Host "Python installed with success"
	}

	Write-Host "Set firewall settings"
	netsh firewall set icmpsetting 8 enable
	netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes
	netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in localport=5986 protocol=TCP action=allow
	netsh advfirewall firewall set rule group="Remote Volume Management" new enable=yes
	netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=yes
	netsh advfirewall firewall set rule group="Remote Event Log Management" new enable=yes

	write-Host "Installing HYPER-V"
	Install-WindowsFeature -Name Hyper-V -IncludeManagementTools 
	if (($DomainName -ne '') -and ($DomainUser -ne '')) {
		Write-Host "Add computer to domain"
		Add-Computer -DomainName $DomainName -Credential $DomainUser -Restart
	}
}

Write-Host "Add users to domain"
cmd /c "for %i in ($UsersList) do net localgroup Administrators %i /add" 
$hyperv = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online
if($hyperv.State -eq "Enabled") {
	Write-Host "Creating private switch"
	New-VMSwitch -Name Private -SwitchType Private -Notes 'Private network - VMs only'

	Write-Host "Creating internal switch"
	New-VMSwitch -Name Internal -SwitchType Internal -Notes 'Parent OS, and internal VMs'

	Write-Host "Set IP to internal switch"
	Get-NetAdapter -Name "vEthernet (Internal)" | New-NetIPAddress -AddressFamily ipv4 -IPAddress 192.168.0.1 -PrefixLength 24

	Write-Host "Set external switch"
	$corpnet=Get-NetRoute | ? DestinationPrefix -eq '0.0.0.0/0' | Get-NetIPInterface | Where ConnectionState -eq 'Connected' | Get-NetAdapter -Physical | Select-Object -First 1
	New-VMSwitch -Name External -NetAdapterName $corpnet.Name -AllowManagementOS $true
}
