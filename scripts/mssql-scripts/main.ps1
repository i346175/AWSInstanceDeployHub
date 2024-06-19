# MSSQL provisioning functions

function global:install-mssql {
    try {
        write-output (Format-LogMessage(">>>>>>>>>> Started execution of Install MSSQL Function at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
        $Global:serviceType = $($args[0])
        # download sql installer artifact
        & $mssqlScriptsFolder\mssql_artifact_downloader.ps1
        # install sql server
        & $mssqlScriptsFolder\mssql_installer.ps1
        write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Install MSSQL function at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
    } catch {
        (Format-LogMessage( $_ | Out-String)) | fl -Force | Out-File -Append $logFile
        throw "Install MSSQL function Error! See $logFile for details"
    }
}
<#

# This code is being retired. Matt R. 1/29/2024.

function global:install-wsfc {
    try {
        write-output (Format-LogMessage(">>>>>>>>>> Started execution of Install WSFC function at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
        # install WSFC feature
        & $mssqlScriptsFolder\wsfc_feature_installer.ps1
        # restart node to enable WSFC feature
        write-output (Format-LogMessage(">>>>>>>>>> Start Restart-Computer at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
        Restart-Computer -Force
    } catch {
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "Install WSFC function Error! See $logFile for details"
    } finally {
        write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Install WSFC function at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
    }
}

function global:build-cluster {
    try {
        write-output (Format-LogMessage(">>>>>>>>>> Started execution of Build Cluster function at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
        # create cluster on master node via a scheduled task
        & $mssqlScriptsFolder\create_cluster.ps1
        write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Build Cluster function at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
    } catch {
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "Build Cluster function Error! See $logFile for details"
    }
}
#>
