param(
    $TemplateType
)

function log() {
    param (
     [string]$string = "",
     [string]$color,
     [bool]$quiet = $false
      )
        $logstring = ($(Get-Date).toString())+" : "+$string
        if(! $quiet)
            {
             if($color)
                {
                 Write-Host $logstring -BackgroundColor $color
                }
             else
                {
                 Write-Host $logstring
                }
            }
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\install_foservice.log"
}

$camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig"
if ($TemplateType -eq "ClusterTemplate") {
    $resourceToSignal = 'ClusterCreationWaitCondition'
} elseif ($TemplateType -eq "AddNodeTemplate") {
    $resourceToSignal = 'AddNodeToClusterWaitCondition'
}    

$exitcode = 0
$checkFeature = get-windowsfeature -Name Failover-Clustering
if($checkFeature.installstate -like "Available")
{
    $installStatus = Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools
    Start-Sleep -Seconds 30
    $featureState = get-windowsfeature -Name Failover-Clustering
    $logstring = "InstallStatus: {0}. Restart Needed: {1}. Success: {2}" -f $featureState.installstate, $featureState.restartneeded, $featureState.success
    log $logstring
    if($featureState.installstate -like "InstallPending"){
        log "Failover Clustering is pending a restart."
    }
    else{
        $doublecheckFeature = get-windowsfeature -Name Failover-Clustering
        log "doublecheck:"
        log $doublecheckFeature
        if($doublecheckFeature -like "InstallPending")
        {
            log "Secondary check shows Failover Clustering is pending a restart."
        }
        else{
            log "Failover Clustering failed to install."
            $exitcode = 1
        }
    }
} elseif ($checkFeature.installstate -ne "Installed") {
    log "Failover Clustering in unknown state."
    log $checkFeature
    $exitcode = 1
} 

# Commenting out. The cluster wait condition needs to be triggered by build_cluster.ps1.

#$ProxyVar = $env:https_proxy
#$env:https_proxy = ''
#log "Signaling CFN and Initiating Reboot."
#cfn-signal.exe -e $exitCode --region $camConfig.awsRegion --resource $resourceToSignal --stack $camConfig.stackName
#$env:https_proxy = $ProxyVar
log "Initiating Reboot."
Restart-Computer -Force
