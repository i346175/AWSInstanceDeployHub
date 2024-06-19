function Main {
    Generate-RandomPassword
    Set-StoreProcedure
    Install-Certificates
}

function Install-Certificates {
    $hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
    # read the cluster node address file for ips
    & C:\cfn\temp\get_cluster_nodes_addresses.ps1
    if ($hostIP -eq $MasterPrivateIP) {
        $ComputerNames = (get-clusternode).Name
        foreach($node in $ComputerNames) {
            Write-Output "Creating cert on computer: [$node] at: $( Get-Date -format 'u' )"
            Invoke-sqlcmd -ServerInstance "$node,$SQLCustomPort" -Database "master" -Query $createCert -QueryTimeout 10 -Username $user -Password $password -TrustServerCertificate
            Invoke-sqlcmd -ServerInstance "$node,$SQLCustomPort" -Database "master" -Query $installCert -QueryTimeout 10 -Username $user -Password $password -TrustServerCertificate

            $execCmd = "
                USE master;
                EXEC dbo.CreateEndpointCert '\\$node\C$\cfn', '$SQLCertificatePwd'"

            Invoke-sqlcmd -ServerInstance "$node,$SQLCustomPort" -Database "master" -Query $execCmd -QueryTimeout 10 -Username $user -Password $password -TrustServerCertificate
            Invoke-sqlcmd -ServerInstance "$node,$SQLCustomPort" -Database "master" -Query "SELECT name FROM sys.certificates" -QueryTimeout 10 -Username $user -Password $password -TrustServerCertificate
        }
        foreach($node in $ComputerNames) {
            foreach($peerNode in $ComputerNames) {
                if( $node -ne $peerNode ) {
                    Write-Output "Installing certificate of [$peerNode] on [$node] at: $( Get-Date -format 'u' )"
                    $installCmd = "
                        USE master;
                        EXEC dbo.InstallEndpointCert '$peerNode', '\\$peerNode\C$\cfn', '$SQLCertificatePwd'"

                    Invoke-sqlcmd -ServerInstance "$node,$SQLCustomPort" -Database "master" -Query $installCmd -QueryTimeout 10 -Username $user -Password $password -TrustServerCertificate
                }
            }
        }
    }
}

function Set-StoreProcedure {
    $Global:createCert = "
        USE [master]
        GO

        /****** Object:  StoredProcedure [dbo].[CreateEndpointCert]    Script Date: 7/12/2020 5:15:53 PM ******/
        SET ANSI_NULLS ON
        GO

        SET QUOTED_IDENTIFIER ON
        GO

        IF EXISTS( SELECT 1 FROM sys.objects WHERE name = 'CreateEndpointCert')
            DROP PROCEDURE CreateEndpointCert
        GO

        CREATE PROCEDURE [dbo].[CreateEndpointCert]
        @ShareName SYSNAME ,
        @StrongPassword SYSNAME
        AS BEGIN

            --This must be executed in the context of Master
            IF (DB_NAME() <> 'master')
            BEGIN
            PRINT N'This SP must be executed in master. USE master and then retry.'
            RETURN (-1)
            END

            DECLARE @DynamicSQL varchar(1000);
            DECLARE @CompName varchar(250);
            DECLARE @HasMasterKey INT;
            SELECT @CompName = CONVERT(SysName, SERVERPROPERTY('MachineName'));

            -- Only create a master key if it doesn't already exist

            SELECT @HasMasterKey = is_master_key_encrypted_by_server from sys.databases where name = 'master'
            IF (@HasMasterKey = 0)
            BEGIN
            --Create a MASTER KEY to encrypt the certificate.
            SET @DynamicSQL = CONCAT('CREATE MASTER KEY ENCRYPTION BY PASSWORD = ' , QUOTENAME(@StrongPassword, ''''));
            EXEC (@DynamicSQL)
            END

            --Create the certificate to authenticate the endpoint
            IF EXISTS (SELECT name from sys.certificates WHERE name = QUOTENAME(@CompName + '-Cert'))
            BEGIN
            SET @DynamicSQL = CONCAT('DROP CERTIFICATE ', QUOTENAME(@CompName + '-Cert'));
            EXEC (@DynamicSQL);
            END
            SET @DynamicSQL = CONCAT('CREATE CERTIFICATE ', QUOTENAME(@CompName + '-Cert'), ' WITH SUBJECT = ', QUOTENAME(@CompName, '''')) ;
            EXEC (@DynamicSQL);

            --Create the database mirroring endpoint authenticated by the certificate.
            SET @DynamicSQL =
            CONCAT('CREATE ENDPOINT AlwaysOn_EP
            STATE = STARTED
            AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL)
            FOR DATABASE_MIRRORING (AUTHENTICATION = CERTIFICATE ',QUOTENAME(@CompName + '-Cert'), ' , ENCRYPTION = REQUIRED ALGORITHM AES, ROLE = ALL)');
            EXEC (@DynamicSQL);

            --Back up the certificate to a common network share for import into other nodes in the cluster
            SET @DynamicSQL = CONCAT('BACKUP CERTIFICATE ',QUOTENAME(@CompName + '-Cert'),' To FILE = ', QUOTENAME( @ShareName + '\SQL-' + @CompName + '.cer', ''''));
            EXEC (@DynamicSQL);
        END
        GO"

    $Global:installCert = "
        USE [master]
        GO

        /****** Object:  StoredProcedure [dbo].[InstallEndpointCert]    Script Date: 7/12/2020 5:15:57 PM ******/
        SET ANSI_NULLS ON
        GO

        SET QUOTED_IDENTIFIER ON
        GO


        IF EXISTS( SELECT 1 FROM sys.objects WHERE name = 'InstallEndpointCert')
            DROP PROCEDURE InstallEndpointCert
        GO

        CREATE PROCEDURE [dbo].[InstallEndpointCert]
        @CompName SYSNAME,
        @ShareName SYSNAME,
        @StrongPassword SYSNAME
        AS BEGIN
            DECLARE @DynamicSQL varchar(1000);
            DECLARE @MyCompName varchar(250);
            SELECT @MyCompName = CONVERT(SysName, SERVERPROPERTY('MachineName'));
            --Don't need to create LOGINs for the local system
            IF (UPPER(@MyCompName) <> UPPER(@CompName))
            BEGIN
                IF EXISTS (SELECT name from sys.certificates WHERE name = QUOTENAME(@CompName + '-Cert'))
                BEGIN
                    SET @DynamicSQL = CONCAT('DROP CERTIFICATE ', QUOTENAME(@CompName +'-Cert'));
                    EXEC (@DynamicSQL);
                END

                IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = @CompName + '-Login')
                BEGIN
                    SET @DynamicSQL = CONCAT('CREATE LOGIN ', QUOTENAME (@CompName + '-Login'), ' WITH PASSWORD= ', QUOTENAME( @StrongPassword, ''''));
                    EXEC (@DynamicSQL);
                END

                IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = @CompName + '-User')
                BEGIN
                    SET @DynamicSQL = CONCAT('CREATE USER ', QUOTENAME( @CompName + '-User'), ' FOR LOGIN ', QUOTENAME(@CompName + '-Login'));
                    EXEC (@DynamicSQL);
                END

                IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = @CompName + '-Cert')
                BEGIN
                    SET @DynamicSQL = CONCAT('CREATE CERTIFICATE ', QUOTENAME(@CompName +'-Cert'), ' AUTHORIZATION ', QUOTENAME(@CompName +'-User'), ' FROM FILE = ', QUOTENAME(@ShareName + '\SQL-' + @CompName + '.cer' , ''''));
                    EXEC (@DynamicSQL);
                END

                SET @DynamicSQL = CONCAT('GRANT CONNECT ON ENDPOINT::AlwaysON_EP TO ', QUOTENAME(@CompName +'-Login'));
                EXEC (@DynamicSQL);
            END
        END

        GO"

}

function Generate-RandomPassword {
    Write-Output (">>>>>>>>>> Generate-RandomPassword >>>>>>>>>>")
    $Assembly = Add-Type -AssemblyName System.Web
    $Global:SQLCertificatePwd = [System.Web.Security.Membership]::GeneratePassword(32,0)
    Write-Output ("<<<<<<<<<< Generate-RandomPassword <<<<<<<<<<")
}

Main