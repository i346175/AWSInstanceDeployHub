<# =================================================================================================================================
Description: Powershell script file for deploying flex configuration for CheckGatewayRoutes monitoring [DOMAIN ENVIRONMENT]
Author: Siva Kasina

Version Date        Ticket      Details
1.0     11/21/2023  CSCI-4017   First version

# =================================================================================================================================#>

Clear-Host
$env:https_proxy = ''
$s3Bucket = $env:aws_envt + "-dbsql-rpl"

$sourcePath = "s3://$s3bucket/NewRelic/FlexIntegrations"
$destNR = 'C:\Program Files\New Relic\newrelic-infra\integrations.d'
$destPSScripts = 'D:\PowershellScripts'

"server1
server2
server3" -split "`r`n" | ForEach-Object{
    $srv = $_.Trim()
    Invoke-Command -ComputerName $srv -ScriptBlock{
        try{
            $env:https_proxy = ''
            Write-Host "$($env:computername) - NewRelic Flex Integration Deployment: STARTED" -ForegroundColor Green
            Write-Host "`tCopying files to the server $($env:computername)..." -ForegroundColor Yellow
            aws s3 cp "$($using:sourcePath)/flex-config.yml" "$($using:destNR)\flex-config.yml" --no-progress
            aws s3 cp "$($using:sourcePath)/CheckGatewayRoutes.ps1" "$($using:destPSScripts)\CheckGatewayRoutes.ps1" --no-progress
            Write-Host "`tRestarting NewRelic Service..." -ForegroundColor Yellow
            Restart-Service  newrelic-infra
            Write-Host "$($env:computername) - NewRelic Flex Integration Deployment: COMPLETED..." -ForegroundColor Green
        }
        catch{
            $_ | Format-List -Force
        }
    }
}
