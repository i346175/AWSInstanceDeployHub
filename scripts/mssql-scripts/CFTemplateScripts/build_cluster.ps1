<#
    Script to create new cluster.
#>

function log() {
    param (
        [string]$string = "",
        [string]$color,
        [bool]$quiet = $false
    )
    $logstring = ($(Get-Date).toString()) + " : " + $string
    if (! $quiet) {
        if ($color) {
            Write-Host $logstring -BackgroundColor $color
        }
        else {
            Write-Host $logstring
        }
    }
    #$logLocation = ($myInvocation.InvocationName).Split(".")[1].split('\')[1]
    Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\clusterBuilder.log"
}

$exitCode = 2
try {    
    log "###########################################################################`r`n"
    log "[Build_Cluster] running under account [$env:userdomain\$env:username]"
    log "###########################################################################`r`n"

    # read the cluster node address file for ips
    $clusterConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig\clusterConfig"
    $camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig"
    if ($clusterConfig.worker2PrimaryIP) {
        log "Three node cluster. Setting configuration."
        $threeNodes = $true
        $Worker1PrivateIP = $clusterConfig.worker1PrimaryIP
        $Worker2PrivateIP = $clusterConfig.worker2PrimaryIP
    }
    else {
        log "Two node cluster. Setting configuration."
        $threeNodes = $false
        $Worker1PrivateIP = $clusterConfig.worker1PrimaryIP
    }

    if ($threeNodes) {
        $nodes = @($clusterConfig.mainPrivateIP, $clusterConfig.Worker1PrimaryIP, $clusterConfig.Worker2PrimaryIP)
        $clusterIps = @($clusterConfig.mainSecondaryIP.split(',')[0], $clusterConfig.worker1SecondaryIP.split(',')[0], $clusterConfig.worker2SecondaryIP.split(',')[0])
    }
    else {
        $nodes = @($clusterConfig.mainPrivateIP, $clusterConfig.Worker1PrimaryIP)
        $clusterIps = @($clusterConfig.mainSecondaryIP.split(',')[0], $clusterConfig.worker1SecondaryIP.split(',')[0])
    }
    
    #build cluster OU
    $domainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
    $TempVar = $domainName.Split('.')
    $ctr = 0
    $domDCString = ""
    while ($ctr -lt $TempVar.Count) {
        $domDCString += ",DC="
        $domDCString += $TempVar[$ctr]
        $ctr++
    }
    $domOuString = $TempVar[0]
    $clusterOU = "DB Cluster Names"
    $serversOU = "Servers"
    $ouPath = "OU=$clusterOU,OU=$serversOU,OU=$domOuString" + "$domDCString"
    $Global:ClusterOUName = "CN=$($camConfig.stackName),OU=$clusterOU,OU=$serversOU,OU=$domOuString" + "$domDCString"

    log "Cluster build params:`r`nNodes: [$nodes],`r`nCluster IPs: [$clusterIps],`r`nCluster OU: [$ClusterOUName]"
    
    # check first if the worker nodes are up first before proceeding with the new cluster command
    log "Started checking worker nodes are online at: $(Get-Date -format 'u')"
    # check every 30 secs for 15 mins
    $counter = 0
    $sleepTime = 30
    $iterations = 30
    log "Iteration [$counter] of checking worker nodes"
    $worker1Connected = test-netconnection  $Worker1PrivateIP -port 135 -informationlevel quiet
    if ($threeNodes) {
        $worker2Connected = test-netconnection  $Worker2PrivateIP -port 135 -informationlevel quiet
        while ((!$worker1Connected -or !$worker2Connected) -and $counter -lt $iterations) {
            # if either worker is not yet online
            $counter++
            Start-Sleep -s $sleepTime
            log "Iteration [$counter] of checking worker nodes"
            $worker1Connected = test-netconnection  $Worker1PrivateIP -port 135 -informationlevel quiet
            $worker2Connected = test-netconnection  $Worker2PrivateIP -port 135 -informationlevel quiet
        }
        
    }
    while ((!$worker1Connected) -and $counter -lt $iterations) {
        # if either worker is not yet online
        $counter++
        Start-Sleep -s $sleepTime
        log "Iteration [$counter] of checking worker nodes"
        if ($counter -le 10) {
            $worker1Connected = test-netconnection  $Worker1PrivateIP -port 135 -informationlevel quiet
        }
        else {
            $test1 = test-netconnection  $Worker1PrivateIP
            $worker1Connected = test-netconnection  $Worker1PrivateIP -port 135 -informationlevel quiet
            log $test1
        }
    }

    if ($counter -ge $iterations) {
        # abort if max iterations limit were reached
        log "MSSQL Cluster build error! Atleast one worker node failed to come online"
        $exitCode = 1
    }
    else {
        # add workers to trustedhosts - to improve the odds of contacting nodes during cluster build command
        log "Adding worker nodes to trusted hosts"
        if ($threeNodes) {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$Worker1PrivateIP,$Worker2PrivateIP" -Concatenate -Force
        }
        else {
            # Changing this to be run via Admin session might be necessary if DomainCreds are disabled.
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$Worker1PrivateIP" -Concatenate -Force
        }

        log "Completed checking worker nodes are online at: $(Get-Date -format 'u')"
        log "All worker nodes are online now."
        # Adding retries to mitigate dns propogation delay issues
        $retryCount = 0
        $sleepTime = 120
        $totalRetries = 6
        $clusterCheckName = ""
        while ($retryCount -lt $totalRetries) {
            log "Started cluster creation at: $(Get-Date -format 'u')"
            log "Cluster creation attempt [$retryCount]..."
            
            # redirect all output streams to results object
            $ExecResults = (New-Cluster -Name $ClusterOUName -Node $nodes -NoStorage -StaticAddress $clusterIps -Force -ErrorAction SilentlyContinue *> $null)

            # If experiencing consistent failures, try this. It will log each build attempt fully.
            #$ExecResults = (New-Cluster -Name $ClusterOUName -Node $nodes -NoStorage -StaticAddress $clusterIps -Force -Verbose *>&1)

            # wait $sleeptime seconds for new cluster name to become available
            log "Waiting $sleeptime seconds for new cluster name to become available"
            Start-Sleep -S $sleepTime

            $clusterFqdn = "{0}.{1}" -f $camConfig.stackName, $camConfig.domainSuffix
            $clusterCheck = Get-Cluster $clusterFqdn
            $clusterCheckName = $clusterCheck.Name
            if ($clusterCheckName -ne $camConfig.stackName) {
                log "Cluster creation attempt [$retryCount] failed"
                $retryCount++
                if ($retryCount -lt $totalRetries) {
                    # retry cluster creation if more attempts left
                    log "Waiting [$sleepTime] secs before next attempt"
                    Start-Sleep -s $sleepTime
                }
            }
            else {
                log $ExecResults
                break
            }
        }
        if ($retryCount -ge $totalRetries) {
            log "MSSQL Cluster creation failed after [$retryCount] retry attempts"
            log "MSSQL Cluster Creation Error! New cluster [$($camConfig.stackName)] was not created!"
            $exitCode = 1
        }
        else {
            $exitCode = 0
            log "MSSQL Cluster creation succeded after [$retryCount] retry attempts"
            log "New cluster [$($camConfig.stackName)] created!"
        }
        if ($clusterConfig.fsxWitnessDNSAddress) {
            #wait 5 min for new cluster service to become available
            log "Waiting 5 minutes for new cluster service to become available"
            Start-Sleep -s 300

            # Add the fsx witness as cluster quorum 
            $fsxDnsAddr = $clusterConfig.fsxWitnessDNSAddress
            Set-ClusterQuorum -NodeAndFileShareMajority "\\${fsxDnsAddr}\share" -Cluster $camConfig.stackName

            # Validate the state of the cluster quorum
            $clusterServiceState = (Get-Service -Name ClusSvc -ErrorAction SilentlyContinue).Status
            if ($clusterServiceState -eq "Running"){
                $clusterQuorumValue = Get-ClusterQuorum -Cluster $camConfig.stackName -ErrorAction SilentlyContinue
                if ($clusterQuorumValue){
                    $clusterQuorumState = $clusterQuorumValue.QuorumResource.State
                    if ($clusterQuorumState -eq "Online"){
                        log "Cluster Quorum configuration for [$($camConfig.stackName)] exists and the state is [$clusterQuorumState] "
                        $exitCode = 0
                    } else {
                        # This secondary check here is due to the occasional delay in processing.
                        # It was found in ~5% of builds, but results in failed builds on successful stacks. -MR 4/19/2024.
                        log "Initial attempt to validate cluster failed. Sleeping for 5 minutes."
                        Start-Sleep -Seconds 300
                        $clusterQuorumState = $clusterQuorumValue.QuorumResource.State
                        if ($clusterQuorumState -eq "Online") {
                            log "Cluster Quorum configuration for [$($camConfig.stackName)] exists and the state is [$clusterQuorumState] "
                            $exitCode = 0
                        } else {
                            log "Cluster Quorum State is not equal to running. Current State: [$clusterquorumstate]"
                            $exitCode = 1
                        }
                    }
                } else {
                    log "Cluster Quorum configuration does not exist! - Failure"
                    $exitCode = 1
                }
            } else {
                log "Cluster service is not in the correct state. Current status: [$clusterServiceState]"
                $exitCode = 1
            }
        }        
    }
} catch {
    log $_
} finally {
    if ($exitCode -ne 2) {
        log "Build of Cluster has completed. Exit code is: $exitcode"
        $ProxyVar = $env:https_proxy
        $env:https_proxy = ''
        cfn-signal.exe -e $exitCode --region $camConfig.awsRegion --resource 'ClusterCreationWaitCondition' --stack $camConfig.stackName
        Start-Sleep -Seconds 5
        # Commenting out restarts, for now.
        #log "CFN Signaled. Restarting server."
        $env:https_proxy = $ProxyVar
        #Restart-Computer -Force
    } else {
        log "Exit code is $exitcode. Try/catch never initialized?"
    }
} 
