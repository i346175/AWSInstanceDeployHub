<#
    Script to create new cluster that runs inside a Scheduled Task
#>
param (
    [string]$taskName,
    [string]$clusterName,
    [string]$region,
    [string]$proxy,
    [string]$phzname,
    [string]$environment,
    [string]$logFile
)

try {

    Write-Output "`r`n###########################################################################" | Out-File -Append $logFile
    Write-Output "Scheduled task: [$taskName] running under account [$env:username]" | Out-File -Append $logFile
    Write-Output "###########################################################################`r`n" | Out-File -Append $logFile

    # read the cluster node address file for ips
    & C:\cfn\temp\get_cluster_nodes_addresses.ps1
    $nodes = @($MasterPrivateIP,$Worker1PrivateIP,$Worker2PrivateIP)
    $clusterIps = @($MasterSecondaryIPs[0],$Worker1SecondaryIPs[0],$Worker2SecondaryIPs[0])

    Write-Output ("Cluster build params:`r`nNodes: [$nodes],`r`nCluster IPs: [$clusterIps]") | Out-File -Append $logFile

    # check first if the worker 1 and 2 nodes are up first before proceeding with the new cluster command
    Write-Output ("Started checking worker nodes are online at: $(Get-Date -format 'u')") | Out-File -Append $logFile
    # check every 60 secs for 20 mins
    $counter = 0
    $sleepTime = 60
    $iterations = 20
    Write-Output ("Iteration [$counter] of checking worker nodes") | Out-File -Append $logFile
    $worker1Connected = Test-Connection -ComputerName $Worker1PrivateIP -Quiet
    $worker2Connected = Test-Connection -ComputerName $Worker2PrivateIP -Quiet
    while ((!$worker1Connected -or !$worker2Connected) -and $counter -lt $iterations) { # if either worker is not yet online
        $counter++
        Start-Sleep -s $sleepTime
        Write-Output ("Iteration [$counter] of checking worker nodes") | Out-File -Append $logFile
        $worker1Connected = Test-Connection -ComputerName $Worker1PrivateIP -Quiet
        $worker2Connected = Test-Connection -ComputerName $Worker2PrivateIP -Quiet
    }
    if ($counter -ge $iterations) {
        # abort if max iterations limit were reached
        Write-Output ("MSSQL Cluster build error! Atleast one worker node failed to come online") | Out-File -Append $logFile
    } else {
        Write-Output ("Completed checking worker nodes are online at: $(Get-Date -format 'u')") | Out-File -Append $logFile
        Write-Output ("All worker nodes are online now.") | Out-File -Append $logFile
        # Adding retries to mitigate dns propogation delay issues
        $retryCount = 0
        $sleepTime = 120
        $totalRetries = 6
        $clusterCheckName = ""
        $exitCode = 0
        while ($retryCount -lt $totalRetries) {
            Write-Output ("Started cluster creation at: $(Get-Date -format 'u')") | Out-File -Append $logFile
            Write-Output ("Cluster creation attempt [$retryCount]...") | Out-File -Append $logFile

            # add workers to trustedhosts - to improve the odds of contacting nodes during cluster build command
            Write-Output ("Adding worker nodes to trusted hosts") | Out-File -Append $logFile
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$Worker1PrivateIP,$Worker2PrivateIP" -Concatenate -Force

            #New-Cluster –Name "$clusterName" -Node "$nodes" -AdministrativeAccessPoint DNS -StaticAddress "$clusterIps" -NoStorage | Out-File -Append $logFile

            $ExecResults = (New-Cluster -Name $clusterName -Node $nodes -AdministrativeAccessPoint DNS -StaticAddress $clusterIps -NoStorage *>&1)
            # pipe results object to log file
            $ExecResults | Out-File -Append $logFile

            # wait 2 min for new cluster name to become available
            Write-Output ("Waiting 2 mins for new cluster name to become available") | Out-File -Append $logFile
            Start-Sleep -s 120

            $clusterFqdn = "$clusterName.$phzname"
            $clusterCheck = Get-Cluster $clusterFqdn
            $clusterCheckName = $clusterCheck.Name
            if ($clusterCheckName -ne $clusterName) {
                Write-Output ("Cluster creation attempt [$retryCount] failed") | Out-File -Append $logFile
                $retryCount++
                if ($retryCount -lt $totalRetries) {# retry cluster creation if more attempts left
                    Write-Output ("Waiting [$sleepTime] secs before next attempt") | Out-File -Append $logFile
                    Start-Sleep -s $sleepTime
                }
            } else {
                break
            }
        }
        if ($retryCount -ge $totalRetries) {
            Write-Output ("MSSQL Cluster creation failed after [$retryCount] retry attempts") | Out-File -Append $logFile
            Write-Output ("MSSQL Cluster Creation Error! New cluster [$clusterName] was not created!") | Out-File -Append $logFile
            $exitCode = 1
        } else {
            Write-Output ("MSSQL Cluster creation succeded after [$retryCount] retry attempts") | Out-File -Append $logFile
            Write-Output ("New cluster [$clusterName] created!") | Out-File -Append $logFile
            Write-Output ("Completed cluster build at: $(Get-Date -format 'u')") | Out-File -Append $logFile
        }
        Write-Output ("Started executing cfn-signal with exit code [$exitCode] at: $(Get-Date -format 'u')") | Out-File -Append $logFile
        if ($environment -eq "INTEGRATION") {
            cfn-signal.exe -e $exitCode --region $region --resource 'ClusterCompletionWaitCondition' --stack $clusterName --https-proxy $proxy
        } else {
            $env:https_proxy=''
            cfn-signal.exe -e $exitCode --region $region --resource 'ClusterCompletionWaitCondition' --stack $clusterName
            $env:https_proxy=$proxy
        }
        Write-Output ("Completed executing cfn-signal at: $(Get-Date -format 'u')") | Out-File -Append $logFile
    }
} catch{
    Format-LogMessage($_) | fl -Force | Out-File -Append $logFile
} finally {
    write-output ("Scheduled Task: [$taskName] has completed") | Out-File -Append $logFile
    # code to remove scheduled task here
    # for now we are not removing it - only disabling
    #write-output "Start deleting task: [$taskName]" | Out-File -Append $logFile
    #Unregister-ScheduledTask -TaskName $taskName -Confirm:$False
    #write-output "Completed deleting task: [$taskName]" | Out-File -Append $logFile
} 
