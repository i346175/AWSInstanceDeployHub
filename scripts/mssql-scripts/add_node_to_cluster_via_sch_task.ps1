<#
    Script to add new node to cluster that runs inside a Scheduled Task
#>
param (
    [string]$taskName,
    [string]$clusterName,
    [string]$region,
    [string]$proxy,
    [string]$logFile,
    [string]$roletype
)
try {
    $ProxyVar = $env:https_proxy
    $env:https_proxy = ''
    & "C:\mssql-scripts\send_logs.ps1"

    Write-Output "`r`n###########################################################################" | Out-File -Append $logFile
    Write-Output (Format-LogMessage("Scheduled task: [$taskName] running under account [$env:userdomain\$env:username]")) | Out-File -Append $logFile
    Write-Output "###########################################################################`r`n" | Out-File -Append $logFile

    $domainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
    $Global:clusterFqdn = "$clusterName.$domainName"

    $clusterNodes = @(Get-ClusterNode -Cluster $clusterName)

    $newNode = $env:COMPUTERNAME
    $hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress

    if(!$clusterNodes.Contains($newNode)) {
        Write-Output (Format-LogMessage("Started adding $newNode to cluster: [$clusterName] at: $( Get-Date -format 'u' )")) | Out-File -Append $logFile

        # redirect all output streams to results object
        $ExecResults = (Get-Cluster -Name $clusterFqdn | Add-ClusterNode -Name $hostIP -Verbose *>&1)
        # pipe results object to log file
        Format-LogMessage($ExecResults) | Out-File -Append $logFile

        # basic checking to see if node was added
        $clusterNodes = @(Get-ClusterNode -Cluster $clusterName)
        if ($clusterNodes.Contains($newNode)) {
            Write-Output (Format-LogMessage("Operation to add node to cluster SUCCEEDED at $( Get-Date -format 'u' )")) | Out-File -Append $logFile
        } else {
            Write-Output (Format-LogMessage("Operation to add node to cluster FAILED at $( Get-Date -format 'u' )")) | Out-File -Append $logFile
        }

        Write-Output (Format-LogMessage("Completed adding $newNode to cluster: [$clusterName] at: $( Get-Date -format 'u' )")) | Out-File -Append $logFile
    } else {
        Write-Output (Format-LogMessage("$newNode is already added")) | Out-File -Append $logFile
    }

    cfn-signal.exe -e 0 --region $region --resource 'AddNodeToClusterWaitCondition' --stack $clusterName

} catch {
    Format-LogMessage($_) | fl -Force | Out-File -Append $logFile
    cfn-signal.exe -e 1 --region $region --resource 'AddNodeToClusterWaitCondition' --stack $clusterName
} finally {
    $env:https_proxy = $ProxyVar
    write-output (Format-LogMessage("Scheduled Task: [$taskName] has completed")) | Out-File -Append $logFile
}
