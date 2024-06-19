Clear-Host

try{
Write-Host "$($env:COMPUTERNAME): Installing..."
Start-Process msiexec.exe -Wait -ArgumentList ' /qn /i "<path>\newrelic-infra.msi'

$newRelicInfraFileContent = @"
# New Relic Infrastructure configuration file.
license_key: <licenseKey>
display_name: $($env:COMPUTERNAME)
proxy: proxy.service.cnqr.tech:3128
verbose: 0
log_file: D:\Logs\NewRelic\newrelic_logs.log
custom_attributes:
  env_name: <Environment>
  env_type: <EnvtType>
  RoleType: dbsql
"@

$newRelicInfraFileContent | Out-File "C:\Program Files\New Relic\newrelic-infra\newrelic-infra.yml"

# Step 4: Start the agent.
Start-Service  newrelic-infra
Write-Host "$($env:COMPUTERNAME): COMPLETED..."
} ## Try
catch{
  $_ | Format-List -Force | Out-String
}

