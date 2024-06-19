function Cycle-AdminPassword {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName,
        [Parameter(Mandatory)][ValidateSet("front", "report", "reportmigration", "spend", "tools", "travel")]
        [string]$VPC,
        [Parameter(Mandatory)][ValidateSet("ALL", "clusadmin", "sa_sqlacct", "sa_sqlagentacct", "sa_sqlbackup")]
        [string]$userAccount
    )
    begin{
        . C:\vault\Get-RandomPassword.ps1
        . C:\vault\Get-VaultToken.ps1
        . C:\vault\Set-VaultPassword.ps1
        . C:\vault\Get-VaultPassword.ps1
    }
    process{
        try{
            $account = @($userAccount)
            if($userAccount -eq 'ALL' -and $clusterName -notlike 'EC2AMAZ-*'){ $account = @("clusadmin", "sa_sqlacct", "sa_sqlagentacct", "sa_sqlbackup") }
            if($userAccount -eq 'ALL' -and $clusterName -like 'EC2AMAZ-*'){ $account = @("sa_sqlacct", "sa_sqlagentacct", "sa_sqlbackup") }
            $env:https_proxy = ''
            if($env:aws_envt -eq 'eu2') { $aws_region = 'eu-central-1' }
            elseif ($env:aws_envt -eq 'apj1') { $aws_region = 'ap-northeast-1' }
            else { $aws_region = 'us-west-2' }
            $vault_namespace = "$VPC/dbsql"
            $token = Get-VaultToken -vault_namespace $vault_namespace -aws_region $aws_region
            
            Write-Host "Cluster/Standalone: $clusterName | VPC: $VPC - Cycling Vault Passwords" -ForegroundColor Green
            $account | ForEach-Object{
                $accName = $_
                $usernameCurr = "$clusterName.$env:aws_envt.$VPC.$($accName)".ToLower()
                $usernameOld = "$clusterName.$env:aws_envt.$VPC.$($accName)_old".ToLower()
                $pCurr = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount $accName
                $pNew = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount $accName -type new
                
                If($pNew -eq $pCurr){
                    Write-Warning "Current and New Passwords for the account $accName are SAME.`r`n`tNew Password for this account may not have been generated after last password cycle activity.`r`n`tNo action performed. Commandlet TERMINATED...`r`n"
                    break;
                }

                [securestring]$secStringPassword = $(ConvertTo-SecureString $pCurr -AsPlainText -Force) 
                [pscredential]$Account = New-Object System.Management.Automation.PSCredential ($usernameOld, $secStringPassword)
                Write-Host "$accName`: Moving current secret to _old secret...`t" -NoNewline
                Set-VaultPassword -Account $Account -token $token -vault_namespace $vault_namespace -aws_region $aws_region | Out-Null
                Write-Host "COMPLETED" -ForegroundColor GREEN

                [securestring]$secStringPassword = $(ConvertTo-SecureString $pNew -AsPlainText -Force) 
                [pscredential]$Account = New-Object System.Management.Automation.PSCredential ($usernameCurr, $secStringPassword)
                Write-Host "$accName`: Moving _new secret to current secret...`t" -NoNewline
                Set-VaultPassword -Account $Account -token $token -vault_namespace $vault_namespace -aws_region $aws_region | Out-Null
                Write-Host "COMPLETED" -ForegroundColor GREEN
            }
            Write-Host "`r`n"
        }
        catch{
            throw $_ 
        }
    }
    end{}
}