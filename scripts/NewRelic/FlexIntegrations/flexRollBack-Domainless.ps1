<# =================================================================================================================================
Description: Powershell script file for REMOVING flex configuration [DOMAINLESS ENVIRONMENT]
Author: Siva Kasina

Version Date        Ticket      Details
1.0     12/4/2023   CSCI-4017   First version

# =================================================================================================================================#>

Clear-Host

. C:\vault\Get-AdminPassword.ps1
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
Restart-Service WinRM -Force

$destNR = 'C:\Program Files\New Relic\newrelic-infra\integrations.d'

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
