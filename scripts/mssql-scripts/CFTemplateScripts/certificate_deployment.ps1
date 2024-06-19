function log() {
    param (
       [string]$string = "",
       [string]$color,
       [bool]$quiet = $false
    )
    $logstring = ($(Get-Date).toString()) + " : " + $string
    if (! $quiet) {
       if ($color) {
          Write-Host $logstring -BackgroundColor $color
       }
       else {
          Write-Host $logstring
       }
    }
    Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\certificate_deployment.log"
 }
 
 
 $clusterConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig\clusterConfig"
 $hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
 & C:\\cfn\\temp\\get_cluster_nodes_addresses.ps1
 if ($hostIP -eq $MasterPrivateIP) {
    log "Started certificate_deployment at: $(Get-Date -format 'u')"
    if ($clusterConfig.worker1PrimaryIP) {
       $cluster = $true
    }
    if ($cluster) {
       Import-Module FailoverClusters
    }   
    $srv = $env:COMPUTERNAME
    #initial load for intermediate certificate
    D:\\PowershellScripts\\Cert_Load.ps1 $srv
    $firstCertCheck = Get-ChildItem -Path Cert:\\LocalMachine\\CA\\ | Where-Object { $_.Subject -like "*dbsql*" } | Sort-Object NotAfter | Select-Object -last 1
    if(!$firstCertCheck){
       $status = 0
       $i = 0
       while ($status -eq 0 -and $i -lt 5) {
          Start-Sleep -Seconds 60
          $certInterMediateMostRecent = Get-ChildItem -Path Cert:\\LocalMachine\\CA\\ | Where-Object { $_.Subject -like "*dbsql*" } | Sort-Object NotAfter | Select-Object -last 1
          if ( $certInterMediateMostRecent.count -gt 0 ) {
             $status = 1
          }
          else {
             $status = 0
             $i++
             log "Run #$i Waiting for 60 seconds..."
          }
       }
    }
    #cert load with proper certTTL
    D:\\PowershellScripts\\Cert_Load.ps1 $srv
    Start-Sleep -Seconds 15
    Get-Service -Name MSSQLServer | Restart-Service -Force | Out-Null
    if ($cluster) {
       log "Cluster recognized. Configuring each node:"
       (Get-ClusterNode).Name | Where-Object { $_ -ne $env:COMPUTERNAME } | ForEach-Object {
          $node = $_
          $str = "@{TrustedHosts=$node}"
          $x = winrm set winrm/config/client $str
          $x = NETSH WINHTTP RESET PROXY
          Invoke-Command -ComputerName $node -ScriptBlock {
             Get-Service -Name MSSQLServer | Restart-Service -Force | Out-Null
          }
          log "$node has been configured."
       }
    }
    else {
       Get-Service -Name MSSQLServer | Restart-Service -Force | Out-Null
    }
    log "Completed certificate_deployment at: $(Get-Date -format 'u')"
 }
 else {
    log "Running on a Secondary Node!"
    log "Not executing code for certificate deployment"
    log "See Master node for certificate deployment logs"
 }