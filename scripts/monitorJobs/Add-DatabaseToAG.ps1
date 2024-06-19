using namespace Microsoft.SqlServer.Management.Common;
using namespace Microsoft.SqlServer.Management.Smo;

Function Add-DatabaseToAG{
    param (
        [String[]]$DBexcludelist,
        [String]$BackupPath = 'M:\MSSQL\Backup'
    )
    begin{
        # snewman 20230405 --> This has been moved below to accomodate excluding databases with the 'NoAG' ext property in the process block below.
        # [string]$tempList = $null
        # [string]$excludeList = $null
        # $TempList = "'$($DBexcludelist -join "','")'"
        # $excludeList = "($($TempList))"
    
        # Import-Module SqlServer -DisableNameChecking
        <# snewman 20230405
            I took out a lot of the SqlServer cmdlets below but tried to leave the string commands alone as much as possible (ordinarily I'd do it all in objects)
            so as not to confuse people going forward.
            The reason I did this was because we can guarentee the SqlServer module is on all nodes going forward..but if this gets ported to pscc...we cannot 
            guarentee the sqlserver module is there.  Hence...just use the dll's.  The 'spirit' of the code hasn't been changed...just the method of execution.
        #>

        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
        
        $now = Get-Date -format yyyy-MM-ddTHH-mm-ss-ff
        $logFile = "D:\Logs\Add_New_Database_AG_$($now).log" 
        
        $SqlPort = switch ($env:aws_envt) {
            "integration" {"2020"; break}
            "us2" {"2040"; break}
            "eu2" {"2050"; break}
            "apj1" {"2060"; break}
            "fabian-us" {"2080"; break}
            "uspscc" {"2020"; break}  # snewman 20230405....
            default {"2020"; break}  # snewman 20230405 --> default to 2020...if the envt var is missing anywhere...it's most likely going to be pscc...
        }
    }
    process{
        try{
            if($BackupPath[-1] -eq '\'){ $BackupPath = $BackupPath.TrimEnd('\') }
            Remove-Item "$BackupPath\*-*.bak"

            $srvName = $env:ComputerName 
            $srvCn = [ServerConnection]::new('.');
            $srv = [Server]::new($srvCn);

            # snewman 20230405
            if(!$srv.IsHadrEnabled -or $srv.AvailabilityGroups.Count -eq 0){
                Write-Host "INFORMATION: Server does not have alwayson enabled or there are no availability groups on the computer. Script execution SKIPPED..."
                return;
            }

            # snewman 20230405 --> end
            $sqlAG = $srv.AvailabilityGroups[0].name  # snewman 20230405 --> added the [0]; it will resolve correctly without it...but I've run into issues with this not being specified before...best be specific...
            $SecondaryReplica = ($srv.AvailabilityGroups[0].AvailabilityReplicas | Where-Object {$_.Name -ne $srvName}).Name 

            # snewman 20230405 --> add dbs with 'NoAg' extended property to exclude list..the mere existence of the 'NoAG' property triggers this.
            foreach($database in $srv.Databases | Where-Object{!$_.IsSystemObject -and $_.Status -eq [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal}){
                if($database.ExtendedProperties['NoAG']){
                    $DBexcludelist += $database.Name;
                }
            }

            $TempList = "'$($DBexcludelist -join "','")'"
            $excludeList = "($($TempList))"
            # snewman 20230405  --> end

            #only process if this is the primary
            if($srv.AvailabilityGroups[0].PrimaryReplicaServerName -ne $srv.ComputerNamePhysicalNetBIOS){
                Write-Host "INFORMATION: Server is AlwaysOn Secondary and the script runs only on Primary. Script execution SKIPPED..."
                return;
            }
        
            # $dt = New-Object System.Data.DataTable 
            # $dt = Invoke-Sqlcmd -ErrorAction Stop -Query "SELECT name From sys.databases WHERE database_id > 4 AND group_database_id IS NULL AND source_database_id IS NULL AND state_desc = 'ONLINE' AND name NOT IN $excludeList" -ServerInstance "$srvName,$SqlPort" -Database 'master' 
            $cmd = "SELECT name From sys.databases WHERE database_id > 4 AND group_database_id IS NULL AND source_database_id IS NULL AND state_desc = 'ONLINE' AND name NOT IN $excludeList";
            $dt = $srv.ConnectionContext.ExecuteWithResults($cmd).Tables[0];

            if($null -ne $dt){
                # snewman 20230405 --> I'm assuming this wants to write to both console & file...this doesn't work...the Tee-Object below accomplishes this...
                # Write-output "-----------------------------------------------------------------------------------------------------------------------------------" | Out-File -Append $logFile
                # Write-output "  Database                                               MESSAGE                                                                   " | Out-File -Append $logFile
                # Write-output "-----------------------------------------------------------------------------------------------------------------------------------" | Out-File -Append $logFile

                "-----------------------------------------------------------------------------------------------------------------------------------" | Tee-Object -FilePath $logFile -Append | Write-Output
                "  Database                                               MESSAGE                                                                   " | Tee-Object -FilePath $logFile -Append | Write-Output
                "-----------------------------------------------------------------------------------------------------------------------------------" | Tee-Object -FilePath $logFile -Append | Write-Output
    
                foreach ($name in $dt) {
                    [String]$database = $name.name
                    $filePath = "$BackupPath\$($database)-$($now).bak"

                    If($($srv.Databases[$database]).RecoveryModel -ne 'FULL'){
                        $srv.Databases[$database].RecoveryModel = 'FULL'
                        $srv.Databases[$database].Alter()
                    }
                    
                    #Backup-SqlDatabase -ServerInstance "$srvName,$SqlPort" -Database "$database" -BackupFile $filePath 
                    $cmd = "BACKUP DATABASE [$database] TO DISK = N'$filePath' WITH COMPRESSION;"
                    [void]$srvCn.ExecuteNonQuery($cmd);

                    foreach ($replica in $SecondaryReplica) {
                        #Invoke-Sqlcmd -ErrorAction Stop -Query "ALTER AVAILABILITY GROUP [$sqlAG] MODIFY REPLICA ON '$replica' WITH (SEEDING_MODE = AUTOMATIC);" -ServerInstance "$srvName,$SqlPort" -Database 'master' -AbortOnError 
                        $cmd = "ALTER AVAILABILITY GROUP [$sqlAG] MODIFY REPLICA ON '$replica' WITH (SEEDING_MODE = AUTOMATIC);"
                        [void]$srvCn.ExecuteNonQuery($cmd);

                        try{
                            #Invoke-Sqlcmd -ErrorAction Stop -Query "ALTER AVAILABILITY GROUP [$sqlAG] GRANT CREATE ANY DATABASE;" -ServerInstance "$replica,$SqlPort" -Database 'master' -AbortOnError
                            $repCn = [ServerConnection]::new("$replica,$SqlPort");
                            $cmd = "ALTER AVAILABILITY GROUP [$sqlAG] GRANT CREATE ANY DATABASE;";
                            [void]$repCn.ExecuteNonQuery($cmd);
                        }
                        catch{
                            throw $_ 
                        }
                        finally{
                            $repCn.Disconnect();
                        }
                    }

                    #Invoke-Sqlcmd -ErrorAction Stop -Query "ALTER AVAILABILITY GROUP [$sqlAG] ADD DATABASE [$database];" -ServerInstance "$srvName,$SqlPort" -Database 'master' -AbortOnError
                    $cmd = "ALTER AVAILABILITY GROUP [$sqlAG] ADD DATABASE [$database];"
                    [void]$srvCn.ExecuteNonQuery($cmd);

                    # snewman 20230405
                    #Write-Output "$database   |  Added to Availability Group [$sqlAG] [Primary : $srvName, Secondary Replica's  : $($SecondaryReplica -join ', ')]" | Out-File -Append $logFile
                    "$database   |  Added to Availability Group [$sqlAG] [Primary : $srvName, Secondary Replica's  : $($SecondaryReplica -join ', ')]" | Tee-Object -FilePath $logFile -Append | Write-Output
                }
            }
            else {
                Write-Output "INFORMATION: No New Databases to add to Availability Group"
            }
        }
        catch{
            Write-Output "ERROR: $($_ | Format-List -Force | Out-String)"
            # snewman 20230405 --> throw 'failure' so the job itself shows as failed.
            throw 'failure'
        }
        finally{
            # snewman 20230405  --> just added the finally to terminate the connection
            if($srvCn){
                $srvCn.Disconnect();
            }
        }
    }
    end{
        # snewman 20230405 --> The proper place for this is in the finally block.  There are errors 
        # that can skip an end block...hence why ps created a clean{} block in 7.3 due to this behavior...
        # also..if an error happened before the $srv is set up...this would cause a null reference 
        # error.  That being said..it's 1 database connection...it will get terminated by itself eventually...
        #$srv.ConnectionContext.Disconnect()
    }
}
