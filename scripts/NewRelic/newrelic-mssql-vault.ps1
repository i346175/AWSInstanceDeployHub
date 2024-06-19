Clear-Host
# $fqdn =  [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
$fqdn = [System.Net.Dns]::GetHostEntry([string]$env:computername).HostName 

try{
Write-Host "$($env:COMPUTERNAME): Installing..."
Start-Process msiexec.exe -Wait -ArgumentList '/qn /i "<path>\nri-mssql-amd64.msi'

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

Restart-Service newrelic-infra
Write-Host "$($env:COMPUTERNAME): COMPLETED..."
} ## Try
catch{
  $_ | Format-List -Force | Out-String
}

