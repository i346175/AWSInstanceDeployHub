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
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\run_postbuild_scripts.log"
}

$clusterConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig\clusterConfig"
$camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig"
$hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
$exitCode = 2 
if ($hostIP -eq $clusterConfig.mainPrivateIP) {
    log "Configuring Global Variables."
    log "Global Variables are bad, and you should feel bad. Don't add more. Retire these when possible. -MR"
    $Global:StackName = $camConfig.stackName
    $Global:TemplateType = "ClusterTemplate" 
    $Global:mssqlScriptsFolder= "C:\mssql-scripts\" 
    cd $mssqlScriptsFolder 
    $Global:logsFolder = "$mssqlScriptsFolder\automation_logs\"
    & C:\\cfn\\temp\\get_cluster_nodes_addresses.ps1
    $env:https_proxy='';

    $sqlExists = Get-Item C:\\cfn\\sqlserver*.nupkg -ErrorAction SilentlyContinue
    $sqlServerGot = Get-Item c:\cfn\sqlserver.zip -ErrorAction SilentlyContinue
    if(!$sqlExists.name -and !$sqlServerGot){
        log "Downloading SQL Server Nuget Packages from S3."
        aws s3 cp s3://$($camConfig.s3BucketName)/$($camConfig.repository)/$($camConfig.scripts), "C:\\cfn\\" --no-progress --recursive --exclude "*" --include "sqlserver*.nupkg"
        Get-Item C:\\cfn\\sqlserver*.nupkg | Rename-Item -NewName sqlserver.zip
        $sqlServerGot = Get-Item c:\cfn\sqlserver.zip
    }
    if($sqlServerGot.name){
        $modulePath = Get-Item "C:\\Program Files\\WindowsPowerShell\\Modules\\SqlServer\" -ErrorAction SilentlyContinue
        if(!$modulePath){
            log "Expanding archive for SqlServer module."
            Expand-Archive -Path C:\\cfn\\sqlserver.zip -DestinationPath "C:\\Program Files\\WindowsPowerShell\\Modules\\SqlServer\" -Force
        }
        
        $sqlBuildGot = Get-Item "c:\cfn\Concur.SqlBuild.zip" -ErrorAction SilentlyContinue
        if ($sqlBuildGot.name) {
            $concurBuildPath = Get-item "C:\\Program Files\\WindowsPowerShell\\Modules\\Concur.SqlBuild\" -ErrorAction SilentlyContinue
            if(!$concurBuildPath){
                log "Expanding Archive for Concur.SqlBuild module."
                Expand-Archive C:\\cfn\\Concur.SqlBuild.zip 'C:\\Program Files\\WindowsPowerShell\\Modules\' -Force
            }
            $usrAccnt = "$env:userdomain\sa_dba_prov"
            $sa_cred = (& C:\mssql-scripts\get_secrets.ps1)
            $saPwd = ($sa_cred.SA.password) | Out-String
            $saPwd = $saPwd.trim()
            $PWord = ConvertTo-SecureString -String $saPwd -AsPlainText -Force
            $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $usrAccnt, $PWord
            # Saw similar errors. Carrying this NETSH line over into new script. -MR 2/1/2024.
            # To fix the WinRM http errors for creating PSSession...
            NETSH WINHTTP RESET PROXY | Out-Null
            $FeatureChecker = get-windowsfeature rsat-ad-powershell,rsat-dns-server
            foreach($i in $FeatureChecker){
                if(!$i.Installed){
                    log "Initiating install of ($($i.Name))."
                    $featured = Install-WindowsFeature $i.Name
                }
            }
            $FeatureChecker = get-windowsfeature rsat-ad-powershell,rsat-dns-server
            foreach($i in $FeatureChecker.installstate){
                if(!$i -eq "Installed"){
                    $exitCode = 1
                }
            }
            # This if statement is for 1 node instances, so they can connect to themselves and utilize the invoke-command methodology.
            if(!(test-path HKLM:\SOFTWARE\Policies\Microsoft\Windows\credentialsdelegation\AllowFreshCredentialsWhenNTLMOnly)){
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
            }
            $invokeResults = Invoke-Command -ComputerName $env:COMPUTERNAME -FilePath "C:\mssql-scripts\CFTemplateScripts\initiate_sqlconfig.ps1" -Credential $Credential -Authentication Credssp
            <#
            # The value contained within $invokeResults is still problematic. We're getting SQL service Status Info from scripts within Concur.SqlBuild.
            # If those notifications aren't necessary, they should be de-activated.
            # Due to this, we can't rely upon the code below to give us accurate results. If there's an error within the SQL configuration, it's caught within initiate_sqlconfig.ps1, instead of here.
            # This means there's two locations which signal "PostBuildWaitCondition" : This script, if something errors, or initiate_sqlconfig.ps1 if it succeeds.

            if(!$invokeResults){
                log "Initiate SQLConfig failed. Sending error signal."
                $exitCode = 1
            }
            else {
                log "Exit code recieved from initiate_sqlconfig.ps1 is: $invokeResults"
            }#>
        } else {
            log "Download of Concur.SqlBuild.zip failed."
            $exitCode = 1
        }
    } else {
        log "Download or creation of sqlserver.zip failed."
        $exitCode = 1        
    }
    # Leaving these here, for now. Removal ought to be handled under a different script, like the remove-creds one. That would enable easier auditing of problems when builds fail.
    #Remove-Item C:\\cfn\\sqlserver.zip
    #Remove-Item C:\\cfn\\Concur.SqlBuild.zip
    
    # Success CFN Signals are triggered by build_cluster.ps1.
    # The signalling done here is ONLY for failures prior to that point.
    # Exitcode is intentionally set to an invalid value, for this reason.
    if ($exitCode -ne 2){
        log "CFN Signaled due to failure in run_postbuild_scripts."
        $ProxyVar = $env:https_proxy
        $env:https_proxy = ''
        cfn-signal.exe -e $exitCode --region $camConfig.awsregion --resource 'PostBuildWaitCondition' --stack $camConfig.StackName
        $env:https_proxy = $ProxyVar
    }
    log "Post Build Process has completed."
}
