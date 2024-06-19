function Get-AdminPassword {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName,
        [Parameter(Mandatory)][ValidateSet("front", "report", "reportmigration", "spend", "tools", "travel")]
        [string]$VPC,
        [Parameter(Mandatory)][ValidateSet("clusadmin", "sa", "sa_sqlacct", "sa_sqlagentacct", "sa_sqlbackup")]
        [string]$userAccount,
        [ValidateSet("new", "current", "old")]
        [string]$type = 'current'
    )
    begin{
        . C:\vault\Get-VaultPassword.ps1
        . C:\vault\Get-VaultToken.ps1
    }
    process{
        if($env:aws_envt -eq 'eu2') { $awsregion = 'eu-central-1' }
        elseif ($env:aws_envt -eq 'apj1') { $awsregion = 'ap-northeast-1' }
        else { $awsregion = 'us-west-2' }
        $vaultnamespace = "$VPC/dbsql"
        $envt = $env:aws_envt
        switch ($type)
        {
            "new" { $userAcct = "$($userAccount)_new" ; Break}
            "current" { $userAcct = $userAccount ; Break }
            "old" { $userAcct = "$($userAccount)_old"}
        }
        
        try{
            $env:https_proxy = ''
            $token = Get-VaultToken -vault_namespace $vaultnamespace -aws_region $awsregion 
            $Account = Get-VaultPassword -Name "$clusterName.$envt.$VPC.$userAcct".ToLower() -token $token -vault_namespace $vaultnamespace -aws_region $awsregion
            # $Account.GetNetworkCredential().UserName
            return $Account.GetNetworkCredential().Password
        }
        catch{
            Write-Error ">>>>> Unable to find secret: $clusterName.$envt.$VPC.$userAcct <<<<<"
        }
    }
    end{
    }
} 
