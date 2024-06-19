#Clear-Host  
##### TO BE REPLACED: <path>, <SQLPort>, <Environment> <namespace> <awsregion> #####

# Step 0: Stop the NewRelic agent service.
Stop-Service newrelic-infra -Force
Write-Host "Stopped newrelic-infra agent." -ForegroundColor GREEN

$fqdn = [System.Net.Dns]::GetHostEntry([string]$env:COMPUTERNAME).HostName

# Step 1: Retrieving Vault Token
Write-Output "Retrieving vault token..."
$env:https_proxy = ''
$token = Get-VaultToken -vault_namespace "<namespace>" -aws_region "<awsregion>"

# Step 2: Installing the NewRelic MSSQL Agent
Write-Host "Installing Newrelic MSSQL Agent..."
Start-Process msiexec.exe -Wait -ArgumentList '/qn /i <path>\nri-mssql-amd64.msi'

#These 2 files below are created automatically every time when is nri-mssql.msi installed/updated
#but it overwrite definition in C:\Program Files\New Relic\newrelic-infra\integrations.d\mssql-config.yml
#so it must be removed to use interval setting mssql-config.yml
# Full path of the file
$deletefile1 = 'C:\Program Files\New Relic\newrelic-infra\newrelic-integrations\mssql-win-definition.yml'
$deletefile2 = 'C:\Program Files\New Relic\newrelic-infra\newrelic-integrations\mssql-definition.yml'

#If the $deletefile1 exist, remove it.
if ((Test-Path -Path $deletefile1)) {
     try {
         Remove-Item -Path $deletefile1 -Force
         Write-Host "The file [$deletefile1] has been removed."
     }
     catch {
         throw $_.Exception.Message
     }
 }


#If the $deletefile2 exist, remove it.
if ((Test-Path -Path $deletefile2)) {
     try {
         Remove-Item -Path $deletefile2 -Force
         Write-Host "The file [$deletefile2] has been removed."
     }
     catch {
         throw $_.Exception.Message
     }
 }

# Step 3: Configuring the .yml file for MSSQL agent
$newRelicInfraFileContent = @"
integrations:
  - name: nri-mssql
    env:
      HOSTNAME: $fqdn
      USERNAME: `${Content.data.username}
      PASSWORD: `${Content.data.password}
      ENABLE_BUFFER_METRICS: false
      ENABLE_DATABASE_RESERVE_METRICS: false 
      REMOTE_MONITORING: true
      PORT: <SQLPort>
      TIMEOUT: 0
    interval: 60s
    labels:
        env: <Environment>
        role: dbsql
        name: mssql_server
    inventory_source: config/mssql
variables:
 Content.data:
   vault:
    http:
     url: https://vault.service.cnqr.tech/v1/tools/dbsql/secret/mssqlnr
     headers:
       X-Vault-Token: $token
"@
$newRelicInfraFileContent | Out-File "C:\Program Files\New Relic\newrelic-infra\integrations.d\mssql-config.yml"

# Step 4: Start the NewRelic agent service.
Start-Service newrelic-infra
Write-Host "Starting newrelic-infra agent. Installation: COMPLETED..." -ForegroundColor GREEN
