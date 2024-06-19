<# =================================================================================================================================
Description: Powershell script file for REMOVING flex configuration [DOMAIN ENVIRONMENT]
Author: Siva Kasina

Version Date        Ticket      Details
1.0     12/4/2023   CSCI-4017   First version

# =================================================================================================================================#>

Clear-Host
$env:https_proxy = ''

$destNR = 'C:\Program Files\New Relic\newrelic-infra\integrations.d'

"server1
server2
server3" -split "`r`n" | ForEach-Object{
    $srv = $_.Trim()
    Invoke-Command -ComputerName $srv -ScriptBlock{
        try{
            $env:https_proxy = ''
            Write-Host "$($env:computername) - NewRelic Flex Integration REMOVAL: STARTED" -ForegroundColor Green
            Get-Service newrelic-infra | Stop-Service -Force
            Write-Host "`tDeleting NewRelic Flex config file on the server $($env:computername)..." -ForegroundColor Yellow
            Remove-Item -Path "$($using:destNR)\flex-config.yml" -Force
            Write-Host "`tRestarting NewRelic Service..." -ForegroundColor Yellow
            Get-Service newrelic-infra | Start-Service
            Write-Host "$($env:computername) - NewRelic Flex Integration REMOVAL: COMPLETED..." -ForegroundColor Green
        }
        catch{
            $_ | Format-List -Force
        }
    }
}
