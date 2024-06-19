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
    Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\initiate_sqlconfig.log"
}
$clusterConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig\clusterConfig"
$camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig"
$hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
$exitCode = 2
if ($hostIP -eq $clusterConfig.mainPrivateIP){
    $usrAccnt = "$env:userdomain\sa_dba_prov"
    $sa_cred = (& C:\mssql-scripts\get_secrets.ps1)
    $saPwd = ($sa_cred.SA.password) | Out-String
    $saPwd = $saPwd.trim()
    $PWord = ConvertTo-SecureString -String $saPwd -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $usrAccnt, $PWord
    # Saw similar errors. Carrying this NETSH line over into new script. -MR 2/1/2024.
    # To fix the WinRM http errors for creating PSSession:
    NETSH WINHTTP RESET PROXY | Out-Null
    log "Importing required modules."
    Import-Module SqlServer, ActiveDirectory, DNSServer
    $modules = Get-Module SqlServer, ActiveDirectory, DNSServer
    if ($modules.length -eq 3) {
        Import-Module "Concur.SqlBuild" -DisableNameChecking -Force
        $sqlBuildImported = Get-Module "Concur.SqlBuild"
        if ($sqlBuildImported.name) {
            if (Get-Service -Name ClusSvc -ErrorAction SilentlyContinue) {
                $ComputerName = (Get-ClusterNode).Name
            }
            else {
                $ComputerName = $env:COMPUTERNAME
            }
            try {
                $ComputerName | Invoke-SqlConfiguration -Credential $Credential
                log "SQL Configuration completed."
            }
            catch {
                log "Invocation of SQL Configuration Failed. Error:"
                log $error
                $exitCode = 1
            }
            try {
                Invoke-RoleConfiguration -ComputerName $ComputerName -Name 'dbsql' -Credential $Credential
                log "Role Configuration completed."
            }
            catch {
                log "Invocation of Role Configuration Failed. Error:"
                log $error
                $exitCode = 1
            }
            Start-Process powershell.exe -ArgumentList "C:\mssql-scripts\CFTemplateScripts\certificate_deployment.ps1" -Wait
                log "Certificate Deployment completed."
                log "Exitcode prior to setting: $exitcode"
                $certCheck = Get-ChildItem -Path Cert:\LocalMachine\CA\ | Where-Object { $_.Subject -like "*dbsql*" } | Sort-Object NotAfter | Select-Object -last 1
                if($certCheck){
                    log "Newly issued certificate found."
                    $exitCode = 0
                } else {
                    log "Trust Hosts not configured by Certificate Deployment. Something went wrong."
                    $exitCode = 1
                }
        } else {
            log "Import of Concur.SQLBuild failed."
            $exitCode = 1
        }
    } else {
        log "Unable to import SQLServer, AD or DNS server modules."
        log $modules.name
        $exitCode = 1
    }
    if ($exitCode -ne 2){
        log "Signaling CFN. Exit Code: $exitcode"
        $ProxyVar = $env:https_proxy
        $env:https_proxy = ''
        cfn-signal.exe -e $exitCode --region $camConfig.awsregion --resource 'PostBuildWaitCondition' --stack $camConfig.StackName
        $env:https_proxy = $ProxyVar
    }
    # Leaving these here, commented out. Removal ought to be handled under a purpose-specific clean-up script. 
    # That would enable easier auditing of problems when builds fail.
    #Remove-Item C:\\cfn\\sqlserver.zip
    #Remove-Item C:\\cfn\\Concur.SqlBuild.zip
}