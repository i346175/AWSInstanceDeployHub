<#
    MSSQL AG Group Builder
    - Creates mirroring endpoints
    - Creates AO AG group
    - Creates Listener
#>

function Main {
    $hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
    & C:\cfn\temp\get_cluster_nodes_addresses.ps1
    if ($hostIP -eq $MasterPrivateIP) { # the code to build cluster only runs on master node
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$MasterPrivateIP,$Worker1PrivateIP,$Worker2PrivateIP" -Concatenate -Force
        $clusterFqdn = "$StackName.$R53PHZName"
        $Global:ClusterNodesArray = (get-clusternode).Name
        $Global:AvailabilityGroupName = "$StackName-AG"
        $Global:ListenerName = "lst-$StackName"
        Create-HadrEndpoint
        Add-AvailabilityGroup
        Create-Listener
    } else {
        Write-Output ("Running on a Worker Node!" ) | Out-File -Append $logFile
        Write-Output ("Not executing code to set up availability group") | Out-File -Append $logFile
        Write-Output ("See master node for set up availability group logs") | Out-File -Append $logFile
    }
}

function Get-ComputerSubNetMask{
    begin{
    }
    process{
        $mask = Get-CIMInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = true" | Where-Object{$null -ne $_.IPSubnet} | Select-Object -First 1 | Select-Object -ExpandProperty IPSubNet;
        if([System.String]::IsNullOrWhiteSpace($mask)){
            Write-Warning "Could not retrieve subnet mask on computer $env:COMPUTERNAME"
            return $null;
        }
        return $($mask| ?{$_ -like "255.*"} | select -First 1);
    }
    end{
    }
} 

function Create-HadrEndpoint {

    Write-Output "Started creating hadr endpoints on all nodes of cluster at: $( Get-Date -format 'u' )" | Out-File -Append $logFile

    $ComputerNames = @($MasterPrivateIP, $Worker1PrivateIP, $Worker2PrivateIP)

    foreach($node in $ComputerNames) {
        try {

            Write-Output "Start creating hadr endpoint on node: [$node] at: $( Get-Date -format 'u' )" | Out-File -Append $logFile

            [system.reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
            [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
            [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
            [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

            $cmd = "
                    IF (SELECT state FROM sys.endpoints WHERE name = 'AlwaysOn_EP') <> 0
                    BEGIN
                        ALTER ENDPOINT [AlwaysOn_EP] STATE = STARTED
                    END
                    GO

                    IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='AlwaysOn_health')
                    BEGIN
                      ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON)
                    END
                    IF NOT EXISTS(SELECT * FROM sys.dm_xe_sessions WHERE name='AlwaysOn_health')
                    BEGIN
                      ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START
                    END

                    GO
                    "
            $srv = New-Object Microsoft.SqlServer.Management.Smo.Server "$node,$SQLPort"
            $srv.ConnectionContext.LoginSecure = $false
            $srv.ConnectionContext.set_Login("sa")
            $srv.ConnectionContext.set_Password($SQLSAPwd)
            $srv.ConnectionContext.Connect()
            [void]$srv.ConnectionContext.ExecuteNonQuery($cmd)
            Write-Output "Completed creating HADR Endpoint on node: [$node]" | Out-File -Append $logFile
        } catch {
            Write-Output "Create HADR Endpoint function Error!" | Out-File -Append $logFile
            $_ | fl -Force | Out-File -Append $logFile
        } finally {
            $srv.ConnectionContext.Disconnect()
        }
    }

    Write-Output "Completed creating hadr endpoints on all nodes of cluster at: $( Get-Date -format 'u' )" | Out-File -Append $logFile

}

function Add-AvailabilityGroup{

    Write-Output "Started adding availability group [$AvailabilityGroupName] at: $( Get-Date -format 'u' )" | Out-File -Append $logFile

    try{

        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlEnum")

        $primary = $env:COMPUTERNAME
        # make sure primary node is the first element of the array so its set up in synchronous mode
        $nodeArray = [System.Collections.ArrayList]$ClusterNodesArray
        $nodeArray.Remove($primary)
        $nodeArray.Insert(0,$primary)

        $srv = New-Object Microsoft.SqlServer.Management.smo.Server "$primary,$SQLPort"
        $srv.ConnectionContext.LoginSecure = $false
        $srv.ConnectionContext.set_Login("sa")
        $srv.ConnectionContext.set_Password($SQLSAPwd)
        $srv.ConnectionContext.Connect()
        $grp = New-Object Microsoft.SqlServer.Management.smo.AvailabilityGroup $srv, $AvailabilityGroupName
        $grp.AutomatedBackupPreference = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupAutomatedBackupPreference]::Primary
        #$grp.DtcSupportEnabled

        foreach($Replica in $nodeArray){
            Write-Output "Started adding availability replica [$Replica] to group object at: $( Get-Date -format 'u' )" | Out-File -Append $logFile
            $rep = new-object Microsoft.SqlServer.Management.smo.AvailabilityReplica $grp, "$Replica"
            $endPointPort = "5022"
            $rep.EndpointUrl = "TCP://$Replica" + "." + "$R53PHZName" + ":" + "$endPointPort"
            $rep.FailoverMode = [Microsoft.SqlServer.Management.smo.AvailabilityReplicaFailoverMode]::Automatic
            $rep.AvailabilityMode = [Microsoft.SqlServer.Management.smo.AvailabilityReplicaAvailabilityMode]::SynchronousCommit
            $rep.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.smo.AvailabilityReplicaConnectionModeInPrimaryRole]::AllowAllConnections
            $rep.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.smo.AvailabilityReplicaConnectionModeInSecondaryRole]::AllowAllConnections
            Write-Output "Setting replica availability mode to SynchronousCommit and connection mode to AllowAllConnections" | Out-File -Append $logFile
            #join the replica to the group
            [void]$grp.AvailabilityReplicas.Add($rep);
            Write-Output "Replica [$Replica] added." | Out-File -Append $logFile
        }

        $grp.Create();

        Write-Output "Availability group [$AvailabilityGroupName] created." | Out-File -Append $logFile

        Start-Sleep -s 10

        Write-Output "Adding worker nodes as replicas to availability group [$AvailabilityGroupName]" | Out-File -Append $logFile

        $workerNodeIps = @($Worker1PrivateIP, $Worker2PrivateIP)

        foreach($ReplicaIp in $workerNodeIps){
            try {
                Write-Output "Started adding replica [$ReplicaIp] to availability group: [$AvailabilityGroupName]" | Out-File -Append $logFile
                $repSrv = New-Object Microsoft.SqlServer.Management.smo.Server "$ReplicaIp,$SQLPort"
                $repSrv.ConnectionContext.LoginSecure = $false
                $repSrv.ConnectionContext.set_Login("sa")
                $repSrv.ConnectionContext.set_Password($SQLSAPwd)
                $repSrv.ConnectionContext.Connect()
                $repSrv.JoinAvailabilityGroup($AvailabilityGroupName)
                Write-Output "Completed adding replica [$ReplicaIp] to availability group: [$AvailabilityGroupName]" | Out-File -Append $logFile
            } catch {
                Write-Output "Error on adding replica [$ReplicaIp] to availability group: [$AvailabilityGroupName]" | Out-File -Append $logFile
                $_ | fl -Force | Out-File -Append $logFile
            } finally {
                $repSrv.ConnectionContext.Disconnect()
            }
        }

    } catch {
        $_ | fl -Force | Out-File -Append $logFile
        throw "See $logFile for details."
    } finally {
        $srv.ConnectionContext.Disconnect()
    }

    Write-Output "Completed adding availability group [$AvailabilityGroupName] at: $( Get-Date -format 'u' )" | Out-File -Append $logFile

}

function Create-Listener {
    Write-Output "Started creating listener [$ListenerName] at: $( Get-Date -format 'u' )" | Out-File -Append $logFile
    try{
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

        $srv = New-Object Microsoft.SqlServer.Management.smo.Server "$env:ComputerName,$SQLPort"
        $srv.ConnectionContext.LoginSecure = $false
        $srv.ConnectionContext.set_Login("sa")
        $srv.ConnectionContext.set_Password($SQLSAPwd)
        $srv.ConnectionContext.Connect()
        $listener = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener $srv.AvailabilityGroups[0], $ListenerName
        $listener.PortNumber = $SQLPort

        $ListenerIPs = @($MasterSecondaryIPs[1], $Worker1SecondaryIPs[1], $Worker2SecondaryIPs[1])

        foreach($ip in $ListenerIPs){
            Write-Output "Started adding ip [$ip] to listener object at: $( Get-Date -format 'u' )" | Out-File -Append $logFile
            $listenerIP = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress($listener)
            $listenerIP.IsDHCP = $false
            $listenerIP.IPAddress = $ip
            $listenerIP.SubnetIP = $ip.Substring(0,$ip.LastIndexOf('.'))+'.0'
            $listenerIP.SubnetMask = $(Get-ComputerSubNetMask) # '255.255.255.0'  #255.255.248.0 ?
            $listener.AvailabilityGroupListenerIPAddresses.Add($listenerIP)
            Write-Output "Completed adding ip [$ip] to listener object at: $( Get-Date -format 'u' )" | Out-File -Append $logFile
        }
        $listener.Create();
        Write-Output "Listener created." | Out-File -Append $logFile
    } catch {
        $_ | fl -Force | Out-File -Append $logFile
        throw "See $logFile for details."
    } finally {
        $srv.ConnectionContext.Disconnect()
    }
    Write-Output "Completed creating listener [$ListenerName] at: $( Get-Date -format 'u' )" | Out-File -Append $logFile

}

Main
