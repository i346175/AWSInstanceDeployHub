param(
    [parameter(Mandatory=$true)][string]$accountName,    
    [parameter(Mandatory=$true)][string]$awsRegion,
    [parameter(Mandatory=$true)][string]$awsEnvironment,
    [parameter(Mandatory=$true)][string]$cRecordName,    
    [parameter(Mandatory=$true)][string]$domainSuffix,
    [parameter(Mandatory=$true)][string]$proxyURL,
    [parameter(Mandatory=$true)][string]$s3Bucket,
    [parameter(Mandatory=$true)][string]$stackName,
    [parameter(Mandatory=$true)][string]$vaultNameSpace,
    [parameter(Mandatory=$true)][string]$scripts,
    [parameter(Mandatory=$true)][string]$repository,
    [string]$mainPrimaryIPAddr,
    [string[]]$mainSecondaryIPAddr,
    [string]$worker1PrimaryIPAddr,
    [string[]]$worker1SecondaryIPAddr,
    [string]$worker2PrimaryIPAddr,
    [string[]]$worker2SecondaryIPAddr,
    [string]$proxyOverride,
    [string]$fsxWitnessDNSAddress
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
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\enable_env_variables.log"
}

log "Started enable_env_variable_for_proxy"
$no_proxy_DRS = "$($env:no_proxy);drs.$($env:aws_region).amazonaws.com;*.s3.$($env:aws_region).amazonaws.com"
[System.Environment]::SetEnvironmentVariable('aws_envt',$awsEnvironment.ToLower(),[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('aws_region',$awsRegion.ToLower(),[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('no_proxy',$no_proxy_DRS,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('r53cname',$cRecordName.ToLower(),[System.EnvironmentVariableTarget]::Machine)
$reg = "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"
Set-ItemProperty -Path $reg -Name ProxyServer -Value $proxyURL
Set-ItemProperty -Path $reg -Name ProxyEnable -Value 1
Set-ItemProperty -Path $reg -Name ProxySettingsPerUser -Value 0
if($proxyOverride)
    {
     Set-ItemProperty -Path $reg -Name HKLMProxyOverride -Value $proxyOverride
    }
$ExecResults = (Get-ItemProperty -Path $reg | select-object -property ProxyServer, ProxyEnable, ProxySettingsPerUser, HKLMProxyOverride )
log $ExecResults
if([bool]$ExecResults.ProxyEnable -and [bool]$ExecResults.ProxyServer)
    {
     log "Proxy Configuration Set"
    }
else
    {
     log "Proxy Configuration Failed"
    }
$configPath = new-item -path "HKLM:\\Software\" -name CamConfig
if(Test-Path -Path "HKLM:\\Software\CamConfig"){
    log "Succeeded in creating CamConfig registry location."
    $clusterPath = new-item -path "HKLM:\\Software\CamConfig" -name clusterConfig
    if(Test-Path -Path "HKLM:\\Software\CamConfig\clusterConfig"){
        log "Succeeded in creating clusterConfig registry location."    
        $configPath = "HKLM:\\Software\CamConfig"
        $clusterPath = "HKLM:\\Software\CamConfig\clusterConfig"
    }
    else{
        log "Failed to create clusterConfig registry location. Exiting."
        Exit-PSHostProcess
    }
}
else{
    log "Failed to create CamConfig registry location. Exiting."
    Exit-PSHostProcess
}

Set-ItemProperty -Path $configPath -Name accountName -Value $accountName
Set-ItemProperty -Path $configPath -Name R53listenerCname -Value $cRecordName
Set-ItemProperty -Path $configPath -Name DomainSuffix -Value $domainSuffix
Set-ItemProperty -Path $configPath -Name s3BucketName -Value $s3Bucket
Set-ItemProperty -Path $configPath -Name stackName -Value $stackName
Set-ItemProperty -Path $configPath -Name scripts -Value $scripts
Set-ItemProperty -Path $configPath -Name repository -Value $repository
Set-ItemProperty -Path $configPath -Name awsregion -Value $awsRegion


if(Get-ItemProperty -Path $configPath -Name stackName)
{
    log "stackName successfully added to registry."
}
else{
    log "Unable to add values to registry. Please investigate."
}
if($mainPrimaryIPAddr){
    Set-ItemProperty -Path $clusterPath -Name mainPrivateIP -Value $mainPrimaryIPAddr    
    if($mainSecondaryIPAddr){Set-ItemProperty -Path $clusterPath -Name mainSecondaryIP -Value $mainSecondaryIPAddr}
    if($worker1PrimaryIPAddr){
        Set-ItemProperty -Path $clusterPath -Name worker1PrimaryIP -Value $worker1PrimaryIPAddr
        Set-ItemProperty -Path $clusterPath -Name worker1SecondaryIP -Value $worker1SecondaryIPAddr
    }
    if($worker2PrimaryIPAddr){
        Set-ItemProperty -Path $clusterPath -Name worker2PrimaryIP -Value $worker2PrimaryIPAddr
        Set-ItemProperty -Path $clusterPath -Name worker2SecondaryIP -Value $worker2SecondaryIPAddr
    }
}
if($fsxWitnessDNSAddress){
    Set-ItemProperty -Path $clusterPath -Name fsxWitnessDNSAddress -Value $fsxWitnessDNSAddress
}

log "Starting creation of Tanium Tags"
If(!(Test-Path -Path 'HKLM:\\Software\\Wow6432Node\\Tanium\\Tanium Client\\Sensor Data\\'))
    {
     log "Registry Path Not Present. Sleeping for 5 minutes."
     start-sleep -seconds 300
    }
If(!(Test-Path -Path 'HKLM:\\Software\\Wow6432Node\\Tanium\\Tanium Client\\Sensor Data\\Tags'))
    {
     $PathCreated = New-Item -Path 'HKLM:\\Software\\Wow6432Node\\Tanium\\Tanium Client\\Sensor Data\\Tags\\'
     log "Created registry path for Tanium Tags"
    }
log "Sleep Timer initiated."
start-Sleep -seconds 15
$tagCreated = New-ItemProperty -Path 'HKLM:\\Software\\Wow6432Node\\Tanium\\Tanium Client\\Sensor Data\\Tags' -Name 'patch-schedule-weekly-Friday-noreboot'
if([bool]$tagCreated)
    {
     log "Completed Tanium Tag Creation"
    }
else
    {
    log "Failed to create Tanium Tag."
    }