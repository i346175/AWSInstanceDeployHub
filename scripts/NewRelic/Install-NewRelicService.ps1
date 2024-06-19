#Clear-Host       

##### TO BE REPLACED: <path>, <licenseKey>, <Environment> #####
# Step 1: Installing the Newrelic service
Write-Host "Installing NewRelic service..."
Start-Process msiexec.exe -Wait -ArgumentList ' /qn /i "<path>\newrelic-infra.msi'


# Step 2: Configuring the .yml file for newrelic service
if(!(Test-Path -Path "D:\Logs\NewRelic")){
    New-Item -ItemType Directory -Path D:\Logs\NewRelic -Force | out-null
}

$newRelicInfraFileContent = @"
# New Relic Infrastructure configuration file.
license_key: <licenseKey>
display_name: $env:COMPUTERNAME
proxy: proxy.service.cnqr.tech:3128
verbose: 0
log_file: D:\Logs\NewRelic\newrelic_logs.log
enable_process_metrics: true
custom_attributes:
  env_name: <Environment>
  RoleType: dbsql
"@
$newRelicInfraFileContent | Out-File "C:\Program Files\New Relic\newrelic-infra\newrelic-infra.yml"

# Step 3: Adding NewRelic tag to registry
$registryTag = "deploy-newrelic-update"

try
{
  Get-Item -path "HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\Tags"
}
catch
{
  New-Item -Path "HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\" -Name "Tags"
}

New-ItemProperty -Path "HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\Tags" -Name "$registryTag"

# Step 4: Restart the NewRelic agent service
Restart-Service  newrelic-infra
Write-Host "Installation: COMPLETED..." -ForegroundColor Green

 
