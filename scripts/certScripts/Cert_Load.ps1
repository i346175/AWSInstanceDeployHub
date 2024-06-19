#Cert_Load.ps1
#load cert into server
[void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
[void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
[void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

<#
Details required for Cert Rotation

-- CNameList - we get this from EC2 Tag
-- ClusterName - from SQL Server query
-- Node/Replica list - from SQL Server query
-- SQLListener - from SQL Server query
-- VPC - from SQL Server query (extended property BackupRootName)

Optional Input Parameter  
-- masternode: This parameter is for cert load when the cluster is built. The cert load will run on CFN master node 
#>
try{
    Write-Output "Deploying Certs..."

    $srv = New-Object Microsoft.SqlServer.Management.smo.Server "."
    $srv.ConnectionContext.TrustServerCertificate = $True
    $srv.ConnectionContext.LoginSecure = $True
    $srv.ConnectionContext.Connect()

    $env:https_proxy = ''
    $erroractionpreference = 'Stop' 
    $error.Clear();

    $masterNode = $args[0]
    $server = $env:COMPUTERNAME

    # only run cert load on masternode for initial server build
    If ( $masterNode -ne $Null -and $masterNode -ne $server ) {   return  }
        #TODO: move port to config.json in rpl
        if($env:aws_envt -eq 'eu2') { $sqlport = '2050'}
            elseif($env:aws_envt -eq 'us2'){ $sqlport = '2040' }
                elseif($env:aws_envt -eq 'uspscc'){ $sqlport = '2020'}
                elseif($env:aws_envt -eq 'apj1'){ $sqlport = '2060'}
                    else{ $sqlport = '2020'}

        $awsregion = $env:aws_region
        $s3Bucket = $env:aws_envt + "-dbsql-rpl"

    #Node list
    $sList = @(); 

    # Get ClusterName
    $sqlQueryClusterName = "SELECT cluster_name clusterName FROM sys.dm_hadr_cluster"
    $clusterName = ($srv.ConnectionContext.ExecuteWithResults($sqlQueryClusterName).Tables[0]).clusterName  

    # Check whether this is a cluster or standalone
    $isCluster = $False
    if ( $clusterName -ne "" ){
        $isCluster = $True
    }
    else {
        $clusterName = $server
        $sList = [PSCustomObject]@{
                Name = $server
                Role = "Primary"
                }
    }

    # Identifiy the node that runs cert load
    # The cert load will run on primary node for sqlagent job cert load
    # The cert load will run on master node for initial server build
    if ( $isCluster -eq $True ) {

        If ( $masterNode -eq $Null ) {
            # Get Node/Replica list
            $sqlQueryReplica = "SELECT RCS.replica_server_name name, ARS.role_desc role
                                FROM  sys.dm_hadr_availability_replica_cluster_states AS RCS,
                                        sys.dm_hadr_availability_replica_states AS ARS
                                Where RCS.replica_id = ARS.replica_id"
            $sList = $srv.ConnectionContext.ExecuteWithResults($sqlQueryReplica).Tables[0]
            $isSecondary = $sList | ?{$_.name -eq $server -and $_.role -eq 'SECONDARY' } 
        }    
        else {
            # get node list
            $sqlQueryReplica = "SELECT RCS.replica_server_name name,
                                CASE 
                                WHEN RCS.replica_server_name = @@servername THEN 'PRIMARY'
                                ELSE 'SECONDARY'
                                END role
                                FROM sys.dm_hadr_availability_replica_cluster_states AS RCS"
            $sList = $srv.ConnectionContext.ExecuteWithResults($sqlQueryReplica).Tables[0]
        }

        if($isSecondary){
            Write-Host "SECONDARY node" $server -ForegroundColor green 
        }
        else{
            # Get SQLListeners
            $sqlQueryListener = "SELECT dns_name listener FROM sys.availability_group_listeners"
            $listenerList = ($srv.ConnectionContext.ExecuteWithResults($sqlQueryListener).Tables[0]).listener
        }
    }

    # Skip the secondary node, only load cert to cluster primary and standalone node
    if ( $masterNode -eq $Null -and $isSecondary ) {   return  }



    # The maximum certTTL for compliance purposes is twelve months 
    # certTTL = 12 months = 365 days = 365 * 24 hours = 8760 hours
    $certTTL = 8760

    # certTTL is also restricted to intermediate cert TTL
    $certInterMediateMostRecent = Get-ChildItem -Path Cert:\LocalMachine\CA\ | ?{$_.Subject -like "*dbsql*"} | sort NotAfter | select -last 1 

    if ( $certInterMediateMostRecent.count -eq 0 ) {
        # first time to load cert, 30 days = 30 * 24 hours = 
        $certTTL = 720
    }
    else {
        foreach($cert in $certInterMediateMostRecent) { 
            $cert.NotAfter
            $startdate = (Get-Date).AddDays(2)
            
            $diff = New-TimeSpan -Start $startdate -End $cert.NotAfter.ToShortDateString()
            $diff.TotalHours 
            $intermediateCertTTL = [Math]::Truncate($diff.TotalHours)
        }

        If ($intermediateCertTTL -lt $certTTL) {
        $certTTL = $intermediateCertTTL
        }
    }

    write-host "Cert Load: certTTL = $certTTL"


    # Get VPC name 
    $sqlQueryVPC = "SELECT  stuff(CAST([value] AS NVARCHAR(128)), 1, charindex('.', CAST([value] AS NVARCHAR(128))), '') VPC from master.sys.extended_properties WHERE name = 'BackupRootName' "
    $vpc = ($srv.ConnectionContext.ExecuteWithResults($sqlQueryVPC).Tables[0]).vpc

    #$clusterNameFQDN = "$clusterName.$vpc.cnqr.tech"
    $clusterNameFQDN = "$clusterName.$env:aws_envt.system.cnqr.tech"
    $vault_namespace = "tools/dbsql"


    # Get EC2 tag: CNameList
    $instance = wget http://169.254.169.254/latest/dynamic/instance-identity/document -UseBasicParsing | ConvertFrom-Json 
    $inst_id = $instance.instanceId 
    $tag_key = "CNameList"
    $CNameListTagValue = (aws ec2 describe-tags --filters "Name=resource-id,Values=$inst_id" | ConvertFrom-Json).Tags | Where-Object Key -eq "$tag_key"  
    $CNameListTagValue= $CNameListTagValue.value.Trim()

    # Return Error if no tag CNameList
    if ( $CNameListTagValue -eq $NULL  ) { Write-Host "server $server has no tag CNameList "; throw 'failure';  return  }
    
    # Set SAN with FQDN
    $AltSubNames = New-Object System.Collections.ArrayList;
    if ( $CNameListTagValue -ne ""  ) {
        $CNameList = $($CNameListTagValue.Split(','))
        foreach($CName in $CNameList){
            if(!$CName.Contains('.')){
                $CName = "$CName.$vpc.cnqr.tech"
            }
            [void]$AltSubNames.Add($CName);
        }
    }

    #Add server names to SAN
    $sList | ForEach-Object{
        $SANItem = $_.name
        $SANItem = "$SANItem.$env:aws_envt.system.cnqr.tech"
        [void]$AltSubNames.Add($SANItem);
    }
    
    #Add listeners to SAN for cluster
    if ( $isCluster -eq $True ) {
        $listenerList | ForEach-Object{
            $SANItem = $_
            
            if ( $SANItem -ne "" -and $SANItem -ne $null ) {
                $SANItem = "$SANItem.$env:aws_envt.system.cnqr.tech"
                [void]$AltSubNames.Add($SANItem);
            }
            else {
                # Return Error if no tag CNameList
                Write-Host "cluster $clusterName has no listener "; throw 'failure';  return 
            }
        }
    } 

    <#
    Write-Host "server           = $server "
    Write-Host "isSecondary      = $isSecondary "
    Write-Host "isCluster        = $isCluster "
    Write-Host "ClusterName      = $ClusterName "
    Write-host "clusterNameFQDN  = $clusterNameFQDN"
    Write-Host "awsregion        = $awsregion "
    Write-Host "certTTL          = $certTTL "
    Write-Host "vault_namespace  = $vault_namespace "
    Write-Host "CNameListTagValue = $CNameListTagValue"
    Write-Host " "
    Write-Host " "
    Write-Host "sList:"
    $sList
    #>

    Write-Host "Cert Load: AltSubNames:"
    $AltSubNames


    #load cert
    $sList | Sort-Object Role | ForEach-Object{
            
        $replicaRole = $($_.Role).ToString()
                
        If($replicaRole -eq "Primary"){
                
            . C:\vault\Run-CreateCertificate.ps1
            . C:\vault\Run-ConfigureCertificate.ps1
            . C:\vault\Invoke-InstallCertificate.ps1

            try{
                
                Run-CreateCertificate -CommonName $clusterNameFQDN -AltNames $AltSubNames -vault_namespace $vault_namespace -aws_region $awsregion -TTL $certTTL 
                Write-Host "$env:COMPUTERNAME`: Certificate creation COMPLETED..." -ForegroundColor Green
                Run-ConfigureCertificate
                Write-Host "$env:COMPUTERNAME`: Certificate configuration COMPLETED..." -ForegroundColor Green
            }
            catch{
                Write-Host "$env:COMPUTERNAME`: Certificate creation/configuration FAILED..." -ForegroundColor Red
                throw $_ 
            }
        }
        Else{
            
            $secondaryNode = $_.Name
                    
            Copy-Item -Path "c:\cfn\$clusterName.pfx"  -Destination "Microsoft.PowerShell.Core\FileSystem::\\$secondaryNode\c`$\cfn\$clusterName.pfx"
        
            $x = NETSH WINHTTP RESET PROXY

            Invoke-Command -ComputerName  $secondaryNode  -ScriptBlock {

                $env:https_proxy = ''

                . C:\vault\Run-CreateCertificate.ps1
                . C:\vault\Run-ConfigureCertificate.ps1
                . C:\vault\Invoke-InstallCertificate.ps1

                try{
                    Invoke-InstallCertificate 
                    Write-Host "$env:COMPUTERNAME`: Certificate install COMPLETED..." -ForegroundColor Green
                    Run-ConfigureCertificate
                    Write-Host "$env:COMPUTERNAME`: Certificate configuration COMPLETED..." -ForegroundColor Green
                }
                catch{
                    Write-Host "$env:COMPUTERNAME`: Certificate configuration failed..." -ForegroundColor Red
                    throw $_ 
                }
            }

        }
    }  


    #Purge old cert from Registry
    $purgeDays = 90
    $purgeDate = (Get-Date).AddDays(-$purgeDays)
    write-host "Cert Load: purgeDate = $purgeDate "

    #Get old certs in registry for purge
    $certPurged = Get-ChildItem -Path Cert:\LocalMachine\My\ | ?{$_.Subject -like "*$clusterNameFQDN*" -and $_.NotAfter -lt $purgeDate} | sort NotAfter 

    #Cleanup old cert
    foreach($cert in $certPurged) { 
        $cert | Select Thumbprint,NotAfter,Subject,SerialNumber 
        $cert | Remove-Item
    }  
}
catch{
    $_
    Write-Output "Cert Deployment script Cert_load.ps1 FAILED"
}
finally {
    $srv.ConnectionContext.Disconnect()
}