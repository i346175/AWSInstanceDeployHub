function Update-AdminPassword {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName,
        [Parameter(Mandatory)][ValidateSet("front", "report", "reportmigration", "spend", "tools", "travel")]
        [string]$VPC,
        [Parameter(Mandatory)]
        [string]$serverName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$cred
    )
    begin{
        . C:\vault\Get-RandomPassword.ps1
        . C:\vault\Get-VaultToken.ps1
        . C:\vault\Set-VaultPassword.ps1
        . C:\vault\Get-VaultPassword.ps1
    }
    process{
        try{
            if($env:aws_envt -eq 'eu2') { $sqlport = '2050' }
            elseif($env:aws_envt -eq 'us2'){ $sqlport = '2040' }
            # Not sure if it is needed since it seems for domainless 
            #elseif($env:aws_envt -eq 'apj1'){ $sqlport = '2060' }
                else{ $sqlport = '2080' }
            $SQLCred = $cred
            If($clusterName -ne $serverName){ 
                $isCluster = 1; $loginName = "clusadmin"; 
            }Else{
                $isCluster = 0; $loginName = "sa_sqlbackup" 
            }

            $pSASA = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount sa_sqlacct -type new
            $pSASAA = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount sa_sqlagentacct -type new
            $pSASB = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount sa_sqlbackup -type new
            If($isCluster){ $pCA = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount clusadmin -type new }
            If($isCluster){ $tempPwd = $pCA }Else{ $tempPwd = $pSASB }
                
            # $pSA = Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount sa -type new
    
            $str = "@{TrustedHosts=""$serverName""}"
            $x = winrm set winrm/config/client $str
            $x = NETSH WINHTTP RESET PROXY
    
            Write-Host "$serverName`: >>>>> PERFORMING PASSWORD ROTATION <<<<<" -ForegroundColor GREEN
            Write-Host "`tPERFORMING WINDOWS/NT-LEVEL ACTIONS" -ForegroundColor GREEN
            
            $PWord = ConvertTo-SecureString $(Get-AdminPassword -clusterName $clusterName -VPC $VPC -userAccount $loginName) -AsPlainText -Force
            $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $loginName, $PWord
            $SQLExists = Invoke-Command -ComputerName $serverName -Credential $Credential -ScriptBlock {
                $SQLExists = (Get-Service -Name MSSQLServer -ErrorAction SilentlyContinue).Count
                
                # 1. UPDATE ALL LOCAL ACCOUNT PASSWORDS EXCEPT CLUSADMIN
                Write-Host "`t  1. Updating Local Accounts passwords..." -NoNewline
                Get-LocalUser -Name "sa_sqlacct" | Set-LocalUser -Password $(ConvertTo-SecureString $using:pSASA -AsPlainText -Force)     
                Get-LocalUser -Name "sa_sqlagentacct" | Set-LocalUser -Password $(ConvertTo-SecureString $using:pSASAA -AsPlainText -Force)
                If($using:isCluster){ Get-LocalUser -Name "sa_sqlbackup" | Set-LocalUser -Password $(ConvertTo-SecureString $using:pSASB -AsPlainText -Force) }
                Write-Host "COMPLETED" -ForegroundColor GREEN

                If($SQLExists){
                    # 2. UPDATE SQLAGENT SERVICE PASSWORD
                    Write-Host "`t  2. Updating SQL Agent Service password..." -NoNewline
                    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
                    $srv = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer . 

                    $service = $srv.Services | Where-Object{$_.name -eq 'SQLSERVERAGENT'}
                    $curr = $service.ServiceAccount.ToLower();
                    if($curr -notlike "*sa_sqlagentacct"){
                        $msg = "The supplied account 'sa_sqlagentacct' does not match the current sqlserveragent account $curr on computer $env:computername."
                        Write-Warning $msg
                        return;
                    }
                    try{
                        $service.ChangePassword($using:pSASAA, $using:pSASAA)
                        $service.Alter()
                        # restart only the agent service...some of the jobs became unresponsive last time we changed the pwd...
                        Get-Service -name SQLSERVERAGENT | Restart-Service -Force -WarningAction SilentlyContinue
                    }
                    catch{
                        $msg = "There was an unhandled exception in changing the password for the sql server agent service on computer $env:computername`r`nThe detailed exception is:`r`m$($_ | Format-List -Force | Out-String)"
                        Write-Warning $msg
                    }
                    Write-Host "COMPLETED" -ForegroundColor GREEN

                    # 3. UPDATE SQLSERVER SERVICE PASSWORD
                    Write-Host "`t  3. Updating SQL Server Service password..." -NoNewline
                    $service = $srv.Services | Where-Object{$_.name -eq 'MSSQLSERVER'}
                    $curr = $service.ServiceAccount.ToLower();
                    if($curr -notlike "*sa_sqlacct"){
                        $msg = "The supplied account 'sa_sqlacct' does not match the current sqlserver service account $curr on computer $env:computername."
                        Write-Warning $msg
                        return;
                    }
                    try{
                        $service.ChangePassword($using:pSASA, $using:pSASA)
                        $service.Alter()
                    }
                    catch{
                        $msg = "There was an unhandled exception in changing the password for the sql server service on computer $env:computername`r`nThe detailed exception is:`r`m$($_ | Format-List -Force | Out-String)"
                        Write-Warning $msg
                    }
                    Write-Host "COMPLETED" -ForegroundColor GREEN
                }
                Else{
                    Write-Host "`t  2. SQL Agent Service not found..! SQL Agent Service Account password reset SKIPPED"
                    Write-Host "`t  3. SQL Server Service not found..! SQL Server Service Account password reset SKIPPED"
                }

                # 4. UPDATE CLUSAMDIN ACCOUNT PASSWORD / SA_SQLBACKUP ACCOUNT FOR STANDALONES
                Write-Host "`t  4. Updating $($using:loginName) local account password..." -NoNewline
                Get-LocalUser -Name $using:loginName | Set-LocalUser -Password $(ConvertTo-SecureString $using:tempPwd -AsPlainText -Force)
                Write-Host "COMPLETED" -ForegroundColor GREEN
                
                $SQLExists
            }
            
            If(!$isCluster){ Start-Sleep -Seconds 10 }
            If($SQLExists){
                Write-Host "`tPERFORMING SQL-LEVEL ACTIONS" -ForegroundColor GREEN
                # $loginName = "sa"
                $sqlQuery = "ALTER CREDENTIAL [$serverName\sa_sqlbackup] WITH IDENTITY = '$serverName\sa_sqlbackup', SECRET = '$($pSASB.Replace("'","''"))';"
                Write-Host "`t  1. Updating sa_sqlbackup proxy credential password..." -NoNewline
                Invoke-Sqlcmd -ServerInstance "$serverName,$sqlport" -Credential $SQLCred -Database master -Query $sqlQuery -TrustServerCertificate
                Write-Host "COMPLETED" -ForegroundColor GREEN
            }

            <#
            $sqlQuery = "ALTER LOGIN [sa] WITH PASSWORD = '$($pSA.Replace("'","''"))', CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;"
            Write-Host "`t  2. Updating SQL sa account password..." -NoNewline
            Invoke-Sqlcmd -ServerInstance "$serverName,$sqlport" -Username $loginName -Password $PWord -Database master -Query $sqlQuery
            Write-Host "COMPLETED`r`n" -ForegroundColor GREEN
            #>
        }
        catch{ 
            throw $_ 
        }
    }
    end{}
}