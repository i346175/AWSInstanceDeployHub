function Create-AdminPassword {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName,
        [Parameter(Mandatory)][ValidateSet("front", "report", "reportmigration", "spend", "tools", "travel")]
        [string]$VPC,
        [Parameter(Mandatory)][ValidateSet("ALL", "clusadmin", "sa_sqlacct", "sa_sqlagentacct", "sa_sqlbackup")]
        [string]$userAccount
    )
    begin{
        . C:\vault\Get-AdminPassword.ps1
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
            Write-Host "Cluster/Standalone: $clusterName | VPC: $VPC - Creating Vault Secrets" -ForegroundColor Green
            $account | ForEach-Object{
                $username = "$clusterName.$env:aws_envt.$VPC.$($_)_new".ToLower()
                Write-Host "INFORMATION: Vault secret [$username] creation...`t" -NoNewline
                [securestring]$secStringPassword = $(Get-RandomPassword -ConvertToSecureString)
                [pscredential]$Account = New-Object System.Management.Automation.PSCredential ($username, $secStringPassword)
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