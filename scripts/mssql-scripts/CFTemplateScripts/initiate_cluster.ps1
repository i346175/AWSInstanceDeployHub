<#
    MSSQL Cluster Builder
    - Creates new cluster on master node
    - Adds a scheduled task that uses sa account as its <run as> user
    - Runs scheduled task
    - Checks scheduled status and updates logs
#>

param (
    [string]$StackName,
    [string]$clusterName,
    [string]$region,
    [string]$proxy,
    [string]$roletype
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
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\initiate_cluster.log"
}

$hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
# read the cluster node address file for ips
& C:\cfn\temp\get_cluster_nodes_addresses.ps1
if ($hostIP -eq $MasterPrivateIP) { # the code to build cluster only runs on master node
    log "Running on Master Node!"
    log "Initiating Cluster Job"
    $clusterConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig\clusterConfig"
    $camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig"
    $usrAccnt = "$env:userdomain\sa_dba_prov"
    log "Retrieving credentials for cluster building."
    $sa_cred = (& C:\mssql-scripts\get_secrets.ps1)
    $saPwd = ($sa_cred.SA.password) | Out-String
    $saPwd = $saPwd.trim()
    $PWord = ConvertTo-SecureString -String $saPwd -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $usrAccnt, $PWord
    log "Configuring CredSSP"
    $HostAddress = "{0}.{1}" -f $env:COMPUTERNAME, $camConfig.domainSuffix
    $wsmanAddr = "wsman/{0}" -f $HostAddress
    Enable-WSManCredSSP -Role "Server" -Force
    Enable-WSManCredSSP -Role "Client" -DelegateComputer $HostAddress -Force
    $ntlmExists = test-path HKLM:\SOFTWARE\Policies\Microsoft\Windows\credentialsdelegation\AllowFreshCredentialsWhenNTLMOnly
    if (!$ntlmExists){
        New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\credentialsdelegation -Name AllowFreshCredentialsWhenNTLMOnly
    }
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\credentialsdelegation -Name AllowFreshCredentialsWhenNTLMOnly -Value 1
    Set-ItemProperty -Name 1 -path HKLM:\SOFTWARE\Policies\Microsoft\Windows\credentialsdelegation\AllowFreshCredentialsWhenNTLMOnly -Value $wsmanAddr -Force
    log "Invoking script to create cluster."
    $featureStatus = (get-windowsfeature failover-clustering).installed
    if($featureStatus){
        Invoke-Command -ComputerName $env:COMPUTERNAME -FilePath "C:\mssql-scripts\CFTemplateScripts\build_cluster.ps1" -Credential $Credential -Authentication Credssp
    }
 } else {
    log "Running on a Worker Node!"
    log "Not executing code to create cluster"
    log "See master node for cluster build logs"
    # Commenting out restarts, for now.
    #Restart-Computer -Force
}