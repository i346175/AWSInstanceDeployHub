<# =================================================================================================================================
Description: Powershell script file for deploying flex configuration for CheckGatewayRoutes monitoring [DOMAINLESS ENVIRONMENT]
Author: Siva Kasina

Version Date        Ticket      Details
1.0     11/21/2023  CSCI-4017   First version

# =================================================================================================================================#>

Clear-Host

. C:\vault\Get-AdminPassword.ps1
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
Restart-Service WinRM -Force

$s3Bucket = $env:aws_envt + "-dbsql-rpl"
$sourcePath = "s3://$s3bucket/NewRelic/FlexIntegrations"
$destNR = 'C:\Program Files\New Relic\newrelic-infra\integrations.d'
$destPSScripts = 'D:\PowershellScripts'

"" -split "`r`n" | ForEach-Object{
    $buildName = $($_.ToString().Trim().Split(','))[0]
    $userAccount = 'sa_sqlbackup'
    $vpc = $($_.ToString().Trim().Split(','))[1]
    $srv = $($_.ToString().Trim().Split(','))[2]

    $PWord =  ConvertTo-SecureString $(Get-AdminPassword -clusterName $buildName -VPC $vpc -userAccount $userAccount) -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userAccount, $PWord
    
    Invoke-Command -ComputerName $srv -Credential $Credential -ScriptBlock{
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
