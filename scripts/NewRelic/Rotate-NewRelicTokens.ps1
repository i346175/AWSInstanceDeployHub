# Rotate-NewRelicTokens.ps1
# 2022-11-23
# Run by the "PS New Relic Token Rotate" SQL Agent Job.
# Create a vault token, add the value in the yml file and pass it to the servers, then restart the service to get the change.
# TO BE REPLACED: <SQLPort>, <Environment> <namespace> <awsregion>

Clear-Host
. C:\vault\Get-VaultToken.ps1

$fqdn = [System.Net.Dns]::GetHostEntry([string]$env:COMPUTERNAME).HostName

Write-Output "Retrieving vault token..."
$env:https_proxy = ''
$token = Get-VaultToken -vault_namespace "<namespace>" -aws_region "<awsregion>"

Write-Output "Updating .yml file with new token..."


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



Write-Output "Updating .yml file with new token..."
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

    $newrelic_log = 'D:\Logs\NewRelic\newrelic_logs.log'
    if(Test-Path $newrelic_log){
        if((Get-Item $newrelic_log).length -gt 1GB){
          Write-Output "Restarting NewRelic service to clear log..."  
          Stop-Service newrelic-infra
          Remove-Item $newrelic_log
          Start-Service newrelic-infra
          Write-Output "COMPLETED..."
        }
        else{
          Write-Output "Restarting NewRelic service..."
          Restart-Service newrelic-infra -Force
          Write-Output "COMPLETED..."
        }
    }

