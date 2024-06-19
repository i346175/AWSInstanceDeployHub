
function Get-Secrets {

    . C:\Vault\Get-VaultToken.ps1
    . C:\Vault\Get-VaultPassword.ps1 
    $env:https_proxy = ''
    $vault_namespace = 'tools/dbsql'
    $aws_region =  $env:aws_region 
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
    [System.Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 

    # Import the TunableSSLValidator module to skip cert check
    Import-Module -Name "C:\mssql-scripts\TunableSSLValidator" 
    Write-Output("Getting password for sa_dba_prov.")
    $sa_user = 'sa_dba_prov'
    $token = Get-VaultToken -vault_namespace $vault_namespace -aws_region $aws_region
    $SAacct = Get-VaultPassword -Name $sa_user -token $token -vault_namespace $vault_namespace -aws_region $aws_region
    #$SApwd =  ConvertTo-SecureString $($SAacct.GetNetworkCredential().Password) -AsPlainText -Force
    $SApwd =  $SAacct.GetNetworkCredential().Password
    
    Write-Output("Getting password for sa_sqlacct.")
    $MSSQLSERVER_user = 'sa_sqlacct'
    $MSSQLSERVERacct = Get-VaultPassword -Name $MSSQLSERVER_user -token $token -vault_namespace $vault_namespace -aws_region $aws_region
    #$MSSQLSERVERpwd =  ConvertTo-SecureString $($MSSQLSERVERacct.GetNetworkCredential().Password) -AsPlainText -Force
    $MSSQLSERVERpwd =  $MSSQLSERVERacct.GetNetworkCredential().Password
    
    Write-Output("Getting password for sa_sqlagentacct.")
    $SQLSERVERAGENT_user = 'sa_sqlagentacct'
    $SQLSERVERAGENTacct = Get-VaultPassword -Name $SQLSERVERAGENT_user -token $token -vault_namespace $vault_namespace -aws_region $aws_region
    #$SQLSERVERAGENTpwd =  ConvertTo-SecureString $($SQLSERVERAGENTacct.GetNetworkCredential().Password) -AsPlainText -Force
    $SQLSERVERAGENTpwd =  $SQLSERVERAGENTacct.GetNetworkCredential().Password
    
    $jsonRequest = [ordered]@{
        MSSQLSERVER= @{
            user = "$MSSQLSERVER_user"
            password = "$MSSQLSERVERpwd"
        }
        SQLSERVERAGENT = @{
            user = "$SQLSERVERAGENT_user"
            password = "$SQLSERVERAGENTpwd"
        }
        "SA" = @{
            user = "$sa_user"
            password = "$SApwd"
        }
        }
    
    return $jsonRequest
}
    
     
Get-Secrets 