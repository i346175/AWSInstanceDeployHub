param(
    [parameter(Mandatory=$true)][string]$SQLPort,
    [string]$Prefix = $env:COMPUTERNAME,
    [parameter(Mandatory=$true)][string]$VPC
)
try{
    . C:\cfn\temp\saCred.ps1 
    $Global:mssqlScriptsFolder="C:\mssql-scripts" 
    Set-Location $mssqlScriptsFolder 
    $Global:logsFolder = "$mssqlScriptsFolder\automation_logs"
    $timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
    $Global:logFile = "$logsFolder\setup_backuprootname_extended_property_log_$timestamp.log"
    $prefixVPC = "$Prefix.$VPC"
    Write-Output (">>>>>>>>>> Creating backup sub-directories at: $(Get-Date -format 'u') >>>>>>>>>>") | Out-File -Append $logFile
    $path = 'M:\MSSQL\Backup'
    'FULL','DIFF','LOG' | ForEach-Object{
        New-Item -Name $_ -Path $path -ItemType Directory | Out-File -Append $logFile
    }    
    Write-Output (">>>>>>>>>> Started setup_backuprootname_extended_property at: $(Get-Date -format 'u') >>>>>>>>>>") | Out-File -Append $logFile
    Start-Sleep -Seconds 120 
    $PropertyName="BackupRootName" 
    Write-Output ("Started setting $PropertyName extended property on master db to: [$prefixVPC]") | Out-File -Append $logFile 
    [system.reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null 
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") 
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") 
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") 
    $srv = New-Object Microsoft.SqlServer.Management.smo.Server "$env:COMPUTERNAME,$SQLPort" 
    $srv.ConnectionContext.TrustServerCertificate = $true
    $srv.ConnectionContext.LoginSecure = $false 
    $srv.ConnectionContext.set_Login("sa") 
    $srv.ConnectionContext.set_Password($SAPassword) 
    $srv.ConnectionContext.Connect() 
    $prop = New-Object Microsoft.SqlServer.Management.Smo.ExtendedProperty $srv.Databases['master'], $PropertyName, $prefixVPC 
    $srv.Databases['master'].ExtendedProperties.Add($prop) 
    $srv.Databases['master'].Alter() 
    Write-Output ("Completed setting $PropertyName extended property on master db to: [$prefixVPC]") | Out-File -Append $logFile 
    write-Output ("<<<<<<<<<< Completed setup_backuprootname_extended_property at: $(Get-Date -format 'u') <<<<<<<<<<") | Out-File -Append $logFile
}
catch{
    Write-Output "Error on setting $PropertyName extended property on master db!" | Out-File -Append $logFile 
    $_ | Format-List -Force
}
finally{
    $srv.ConnectionContext.Disconnect() 
}