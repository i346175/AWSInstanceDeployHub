<# ========================================================================================================================
Description: Script Fixes Missing logins, Mismatched SID and Mismatched Passwords on 3 node Always On Clusters with non default SQL Ports. 

Version Date        Ticket#     Description
1.0     9/29/2021   CSCI-2626   Creation of scripts and jobs
1.1     10/1/2021   CSCI-2722   BUG FIX - SyncLogins job failures due to issue to drop and recreate logins
1.2     7/14/2022   CSCI-3934   BUG FIX - Fix-Missing-And-Mismatch-SQL-Logins.ps1 is failing for logins with CHECK_POLICY = ON
1.3     9/21/2023   CSCI-6347   BUG FIX - Script does not cover CCPS envt and WindowsLogins
1.4     2/8/2024    CSCI-6764   BUG FIX - TrustServerCertificate property added for all SQL connections

Author: Nanda, Siva
======================================================================================================================== #>
Clear-Host
Import-Module SqlServer -DisableNameChecking
[void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
[void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
[void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

$now = Get-Date -format yyyy-MM-ddTHH-mm-ss-ff
$Global:logFile = "D:\Logs\MSSQL_Missing_Login_Fix_$($now).log" #Change the target log file location
$srvName = $env:ComputerName
$SqlPort = switch ($env:aws_envt) {
    "integration" {"2020"; break}
    "us2" {"2040"; break}
    "eu2" {"2050"; break}
    "apj1" {"2060"; break}
    "uspscc" {"2020"; break}
}

Write-Output "ServerName    ReplicaName Login   Message " | Out-File -Append $logFile
Write-Output "----------    ----------- -----   -------" | Out-File -Append $logFile

try{
    $srv = New-Object Microsoft.SqlServer.Management.smo.Server "$srvName,$SqlPort"
    $srv.ConnectionContext.TrustServerCertificate = $true

    #only process if this is the primary
    if($srv.AvailabilityGroups[0].PrimaryReplicaServerName -ne $srv.ComputerNamePhysicalNetBIOS){
        Write-Host "INFORMATION: Server is AlwaysOn Secondary and the script runs only on Primary. Script execution SKIPPED..."
        return;
    }

    $primaryName = $srv.AvailabilityGroups[0].PrimaryReplicaServerName

    foreach($Group in $srv.AvailabilityGroups){
        # SQL Logins
        foreach($login in $srv.Logins | Where-Object{$_.LoginType -eq [Microsoft.SqlServer.Management.smo.LoginType]::SqlLogin -and $_.Name -notlike '##*' -and $_.Name -notlike 'EC2AMAZ-*-Login' -and $_.Name -notin ('newrelic','solarwinds')}){                
            # Get primary SID and password hash.
            $dt = New-Object System.Data.DataTable

            $dt = Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select name, 
                                                sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), sid))             as SID,
                                                sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), password_hash))   as PasswordHash
                                            from sys.sql_logins
                                            where type_desc = 'SQL_LOGIN'
                                            and sid != 0x01
                                            and name = '$($login.name)' " -ServerInstance "$srvName,$SqlPort" -Database 'master'

            if ($dt -ne $null) { 
                # Iterate the secondary replicas.
                $Group.AvailabilityReplicas | ?{$_.Role -eq [Microsoft.SqlServer.Management.smo.AvailabilityReplicaRole]::Secondary} | %{

                    # Set up for comparing this replica to the primary.
                    $replicaName = $_.Name

                    # Does this login not exist on the secondary?
                    $secsrv = new-object Microsoft.SqlServer.Management.smo.Server "$replicaName,$SqlPort"
                    $secsrv.ConnectionContext.TrustServerCertificate = $true
                    $secLogin = $secsrv.Logins[$login.Name]
                    if(!$secLogin){
                        Write-Output "$primaryName  $($replicaName) $($login.name)  Login $($login.name) was not found on Secondary Replica $replicaName. [Login Fixed]" | Out-File -Append $logFile
                        
                        # Create missing login on Replica with Hashed Password and SID from Primary
                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF NOT EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                        BEGIN 
                        CREATE LOGIN [$($login.name)] WITH PASSWORD = $($dt.PasswordHash) HASHED, SID = $($dt.SID), CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF, DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                        END " -ServerInstance "$replicaName,$SqlPort" -Database 'master'

                        # Add Server roles to login
                        foreach ($role in $srv.Roles)
                        {
                        $RoleMembers = $Role.EnumServerRoleMembers()
                            if($RoleMembers -contains $login.Name)
                                    {
                                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                                    }
                        }

                        # Add Server Permissions to login
                        $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$srvName,$SqlPort" -Database 'master'
                        [string]$srvGrant = ''
                        foreach ($name in $srvPermissions)
                        {
                            [string]$srvGrant += $name.name
                        
                        }
                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                    }
                    else {
                        # Get secondary SID and password hash.
                        $dtSec = New-Object System.Data.DataTable

                        $dtSec = Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select name, 
                                                                sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), sid))             as SID,
                                                                sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), password_hash))   as PasswordHash
                                                            from sys.sql_logins
                                                        where type_desc = 'SQL_LOGIN'
                                                            and sid != 0x01
                                                            and name = '$($login.name)' " -ServerInstance "$replicaName,$SqlPort" -Database 'master'

                        # Do the SIDs not match?
                        if ($dt.SID -ne $dtSec.SID) {
                            Write-Output "$primaryName  $($replicaName) $($login.name)  The SIDs for login $($login.Name) do not match. [Login Fixed]" | Out-File -Append $logFile
                            
                            # Drop Mismatched SID Login on Replica and re-create the login with Hashed Password and SID from Primary
                            Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                            BEGIN
                            DROP LOGIN [$($login.name)]
                            CREATE LOGIN [$($login.name)] WITH PASSWORD = $($dt.PasswordHash) HASHED, SID = $($dt.SID), CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF, DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                            END " -ServerInstance "$replicaName,$SqlPort" -Database 'master'

                            # Add Server roles to login
                            foreach ($role in $srv.Roles)
                            {
                            $RoleMembers = $Role.EnumServerRoleMembers()
                            if($RoleMembers -contains $login.Name)
                                    {
                                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                                    }
                            }
                            
                            # Add Server Permissions to login
                            $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$srvName,$SqlPort" -Database 'master'
                            [string]$srvGrant = ''
                            foreach ($name in $srvPermissions)
                            {
                                [string]$srvGrant += $name.name
                            
                            }
                            Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                            }

                        # Do the password hashes not match?
                        if ($dt.PasswordHash -ne $dtSec.PasswordHash) {
                            Write-Output "$primaryName  $($replicaName) $($login.name)  The password hashes for login $($login.Name) do not match. [Login Fixed]" | Out-File -Append $logFile
                            
                            # ALTER Mismatched Password Login on Replica
                            Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                            BEGIN
                                DECLARE @cmd varchar(500);
                                SELECT @cmd = CONCAT('ALTER LOGIN ',QUOTENAME(name),' WITH CHECK_POLICY = ',CASE is_policy_checked WHEN 1 THEN 'ON' ELSE 'OFF' END,', CHECK_EXPIRATION = ',CASE is_expiration_checked WHEN 1 THEN 'ON' ELSE 'OFF' END,';' ) from sys.sql_logins
                                WHERE name = '$($login.name)'
                                ALTER LOGIN [$($login.name)] WITH CHECK_POLICY = OFF;
                                ALTER LOGIN [$($login.name)] WITH PASSWORD = $($dt.PasswordHash) HASHED;
                                EXEC (@cmd)
                            END " -ServerInstance "$replicaName,$SqlPort" -Database 'master'

                            # Add Server roles to login
                            foreach ($role in $srv.Roles)
                            {
                            $RoleMembers = $Role.EnumServerRoleMembers()
                            if($RoleMembers -contains $login.Name)
                                    {
                                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                                    }
                            }

                            # Add Server Permissions to login
                            $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$srvName,$SqlPort" -Database 'master'
                            [string]$srvGrant = ''
                            foreach ($name in $srvPermissions)
                            {
                                [string]$srvGrant += $name.name
                            }
                            Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                        }
                    }

                    $secsrv.ConnectionContext.Disconnect();
                }
            }
        }

        # Windows Logins
        foreach($login in $srv.Logins | Where-Object{$_.Name -like "$($env:aws_envt)\*"}){
            # Iterate the secondary replicas.
            $Group.AvailabilityReplicas | Where-Object{$_.Role -eq [Microsoft.SqlServer.Management.smo.AvailabilityReplicaRole]::Secondary} | ForEach-Object{

                # Set up for comparing this replica to the primary.
                $replicaName = $_.Name

                # Does this login exist on the secondary?
                $secsrv = New-Object Microsoft.SqlServer.Management.smo.Server "$replicaName,$SqlPort"
                $secsrv.ConnectionContext.TrustServerCertificate = $true
                $secLogin = $secsrv.Logins[$login.Name]
                if(!$secLogin){
                    Write-Output "$primaryName  $($replicaName) $($login.name)  Login $($login.name) was not found on Secondary Replica $replicaName. [Login Fixed]" | Out-File -Append $logFile
                    # Create missing login on Replica from Primary
                    Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF NOT EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                    BEGIN
                    CREATE LOGIN [$($login.name)] FROM WINDOWS WITH DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                    END " -ServerInstance "$replicaName,$SqlPort" -Database 'master'

                    # Add Server roles to login
                    foreach ($role in $srv.Roles){
                        $RoleMembers = $Role.EnumServerRoleMembers()
                        if($RoleMembers -contains $login.Name){
                            Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                        }
                    }

                    # Add Server Permissions to login
                    $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$srvName,$SqlPort" -Database 'master'
                    [string]$srvGrant = ''
                    foreach ($name in $srvPermissions){
                        [string]$srvGrant += $name.name                            
                    }
                    Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                }

                $secsrv.ConnectionContext.Disconnect();
            }
        }
    }

    # reverse replica missing login check and fix
    # $replica1= $srv.AvailabilityGroups[0].AvailabilityReplicas[1].name
    # $replica1Conn= new-object Microsoft.SqlServer.Management.smo.Server "$replica1,$SqlPort"
    # $replica2= $srv.AvailabilityGroups[0].AvailabilityReplicas[2].name
    # $replica2Conn= new-object Microsoft.SqlServer.Management.smo.Server "$replica2,$SqlPort"

    $srv.AvailabilityGroups[0].AvailabilityReplicas | ?{$_.Name -ne $srv.ComputerNamePhysicalNetBIOS} | %{
        $replicaName = $_.Name 
        $secsrv = New-Object Microsoft.SqlServer.Management.smo.Server "$replicaName,$SqlPort"
        $secsrv.ConnectionContext.TrustServerCertificate = $true

        # SQL Logins
        foreach($login in $secsrv.Logins | Where-Object{$_.LoginType -eq [Microsoft.SqlServer.Management.smo.LoginType]::SqlLogin -and $_.Name -notlike '##*' -and $_.Name -notlike 'EC2AMAZ-*-Login' -and $_.Name -notin ('newrelic','solarwinds')}){
            $dt2 = New-Object System.Data.DataTable
            $dt2 = Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select name, 
                sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), sid))             as SID,
                sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), password_hash))   as PasswordHash
                    from sys.sql_logins
                    where type_desc = 'SQL_LOGIN'
                    and sid != 0x01
                    and name = '$($login.name)' " -ServerInstance "$replicaName,$SqlPort" -Database 'master'
            if(!($srv.Logins[$login.Name])){

                # Create missing login on Primary with Hashed Password and SID from Secondary
                $checkLogin = get-SqlLogin -ServerInstance $env:ComputerName
                if($login.name -notin $checkLogin.name){
                    Write-Output "$($replicaName)   $($srvName) $($login.name)  Login $($login.name) was not found on Primary replica $srvName. [Login Fixed]" | Out-File -Append $logFile
                }
                Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF NOT EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                    BEGIN 
                    CREATE LOGIN [$($login.name)] WITH PASSWORD = $($dt2.PasswordHash) HASHED, SID = $($dt2.SID), CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF, DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                    END " -ServerInstance "$srvName,$SqlPort" -Database 'master'
                # Add Server roles to login
                foreach ($role in $secsrv.Roles)
                {
                $RoleMembers = $Role.EnumServerRoleMembers()
                    if($RoleMembers -contains $login.Name)
                            {
                                Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$srvName,$SqlPort" -Database 'master'
                            }
                }
                # Add Server Permissions to login
                $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                [string]$srvGrant = ''
                foreach ($name in $srvPermissions)
                {
                    [string]$srvGrant += $name.name

                }
                Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$srvName,$SqlPort" -Database 'master'

                <#
                # Create missing login on Secondary Replica 2 with Hashed Password and SID
                If ($replicaName -eq $replica1) {
                    if(!($replica2conn.Logins[$login.Name])){
                    Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF NOT EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                        BEGIN 
                        CREATE LOGIN [$($login.name)] WITH PASSWORD = $($dt2.PasswordHash) HASHED, SID = $($dt2.SID), CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF, DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                        END " -ServerInstance "$replica2,$SqlPort" -Database 'master'
                        Write-Output "$($replicaName)   $($replica2)        $($login.name)    Login $($login.name) was not found on secondary replica $($replica2). [Login Fixed]" | Out-File -Append $logFile
                        Write-Output "" | Out-File -Append $logFile

                        # Add Server roles to login
                        foreach ($role in $secsrv.Roles)
                        {
                        $RoleMembers = $Role.EnumServerRoleMembers()
                            if($RoleMembers -contains $login.Name)
                                    {
                                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$replica2,$SqlPort" -Database 'master'
                                    }
                        }

                        # Add Server Permissions to login
                        $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                        [string]$srvGrant = ''
                        foreach ($name in $srvPermissions)
                        {
                            [string]$srvGrant += $name.name

                        }
                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$replica2,$SqlPort" -Database 'master'
                        
                }
                }
                # Create missing login on Secondary Replica 1 with Hashed Password and SID
                else {
                    if(!($replica1conn.Logins[$login.Name])){
                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF NOT EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                        BEGIN 
                        CREATE LOGIN [$($login.name)] WITH PASSWORD = $($dt2.PasswordHash) HASHED, SID = $($dt2.SID), CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF, DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                        END " -ServerInstance "$replica1,$SqlPort" -Database 'master'
                        Write-Output "$($replicaName)   $($replica1)        $($login.name)    Login $($login.name) was not found on secondary replica $($replica1). [Login Fixed]" | Out-File -Append $logFile
                        Write-Output "" | Out-File -Append $logFile

                        # Add Server roles to login
                        foreach ($role in $secsrv.Roles)
                        {
                        $RoleMembers = $Role.EnumServerRoleMembers()
                            if($RoleMembers -contains $login.Name)
                                    {
                                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$replica1,$SqlPort" -Database 'master'
                                    }
                                    
                        }

                        # Add Server Permissions to login
                        $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                        [string]$srvGrant = ''
                        foreach ($name in $srvPermissions)
                        {
                            [string]$srvGrant += $name.name
                            

                        }
                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$replica1,$SqlPort" -Database 'master'
                        
                    }
                }
                #>
            }
        }

        # Windows Logins
        foreach($login in $secsrv.Logins | Where-Object{$_.Name -like "$($env:aws_envt)\*"}){
            if(!($srv.Logins[$login.Name])){    
                # Create missing login on Primary from Secondary
                $checkLogin = Get-SqlLogin -ServerInstance $env:ComputerName
                if($login.name -notin $checkLogin.name){
                    Write-Output "$($replicaName)   $srvName    $($login.name)  Login $($login.name) was not found on Primary replica $srvName. [Login Fixed]" | Out-File -Append $logFile
                }
                Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "IF NOT EXISTS (SELECT name from master.sys.server_principals WHERE name = '$($login.name)')
                    BEGIN
                    CREATE LOGIN [$($login.name)] FROM WINDOWS WITH DEFAULT_DATABASE = [$($login.DefaultDatabase)]
                    END" -ServerInstance "$srvName,$SqlPort" -Database 'master'

                # Add Server roles to login
                foreach ($role in $secsrv.Roles){
                    $RoleMembers = $Role.EnumServerRoleMembers()
                    if($RoleMembers -contains $login.Name){
                        Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "ALTER SERVER ROLE $($Role) ADD MEMBER [$($login.name)] " -ServerInstance "$srvName,$SqlPort" -Database 'master'
                    }
                }

                # Add Server Permissions to login
                $srvPermissions= Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query "select state_desc + ' '+permission_name+' TO '+quotename(suser_name(grantee_principal_id)) as name from sys.server_permissions where (suser_name(grantee_principal_id)) = '$($login.name)';" -ServerInstance "$replicaName,$SqlPort" -Database 'master'
                [string]$srvGrant = ''
                foreach ($name in $srvPermissions){
                    [string]$srvGrant += $name.name
                }
                Invoke-Sqlcmd -TrustServerCertificate -ErrorAction Stop -Query $srvGrant -ServerInstance "$srvName,$SqlPort" -Database 'master'
            }
        }
        $secsrv.ConnectionContext.Disconnect();
    }

}
catch{
    throw $_
}
finally{
    if ($srv){
        $srv.ConnectionContext.Disconnect();
    }
}
