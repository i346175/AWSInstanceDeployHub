param(
    [parameter(Mandatory=$true)][string]$vault_namespace,
    [parameter(Mandatory=$true)][string]$awsRegion,
    [parameter(Mandatory=$true)][string]$s3bucket,
    [parameter(Mandatory=$true)][string]$mssqlScriptsFolderName,
    [parameter(Mandatory=$true)][string]$NewRelicKey,
    [parameter(Mandatory=$true)][string]$Envt,
    [parameter(Mandatory=$true)][string]$SQLPort
)

Set-Location C:\vault
. .\Get-VaultToken.ps1
. .\Get-VaultPassword.ps1
$env:https_proxy = ''
$userName = 'newrelic'
$nrSecret = 'mssqlnr'
$mssqlScriptsFolder = "C:\$mssqlScriptsFolderName" 
$logsFolder = "$mssqlScriptsFolder\automation_logs"
$logFile = "$logsFolder\install_NewRelic_log_$timestamp.log"
$dPath = 'D:\PowershellScripts'
$destNR = 'C:\Program Files\New Relic\newrelic-infra\integrations.d'
$timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
$token = Get-VaultToken -vault_namespace $vault_namespace -aws_region $awsRegion
$Account = Get-VaultPassword -vault_namespace $vault_namespace -aws_region $awsRegion -Name $nrSecret -token $token

Write-Output (">>>>>>>>>> Started install_NewRelic at: $(Get-Date -format 'u') >>>>>>>>>>") | Out-File -Append $logFile

$str1 = $Account.GetNetworkCredential().Password
$str1 = $str1.Replace("'","''")
$sqlQuery = "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$userName')
 DROP LOGIN [$userName]
CREATE LOGIN [$userName] WITH PASSWORD=N'$str1', DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[us_english], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;
GRANT CONNECT SQL TO [$userName];
GRANT VIEW SERVER STATE TO [$userName];
GRANT VIEW ANY DEFINITION TO [$userName];"
Invoke-Sqlcmd -Database master -Query $sqlQuery -QueryTimeout 30;

aws s3 cp "s3://$s3bucket/AWSInstanceDeployHub/scripts/NewRelic/" $mssqlScriptsFolder --recursive --quiet

Set-Location $mssqlScriptsFolder
if(!(Test-Path -Path $dPath)){ New-Item -ItemType Directory -Path $dPath -Force | Out-Null }
Move-Item -Path ./Rotate-NewRelicTokens.ps1 -Destination "$dPath\Rotate-NewRelicTokens.ps1" -Force
Move-Item -Path ./FlexIntegrations/CheckGatewayRoutes.ps1 -Destination "$dPath\CheckGatewayRoutes.ps1" -Force
Move-Item -Path ./FlexIntegrations/flex-config.yml -Destination "$destNR\flex-config.yml" -Force

Set-Content -Path ./Install-NewRelicService.ps1 -Value (Get-Content ./Install-NewRelicService.ps1).Replace("<path>","$mssqlScriptsFolder")
Set-Content -Path ./Install-NewRelicService.ps1 -Value (Get-Content ./Install-NewRelicService.ps1).Replace("<licenseKey>","$NewRelicKey")
Set-Content -Path ./Install-NewRelicService.ps1 -Value (Get-Content ./Install-NewRelicService.ps1).Replace("<Environment>","$Envt")
./Install-NewRelicService.ps1

Set-Content -Path ./Install-NewRelicMSSQLAgent.ps1 -Value (Get-Content ./Install-NewRelicMSSQLAgent.ps1).Replace("<path>","$mssqlScriptsFolder")
Set-Content -Path ./Install-NewRelicMSSQLAgent.ps1 -Value (Get-Content ./Install-NewRelicMSSQLAgent.ps1).Replace("<SQLPort>","$SQLPort")
Set-Content -Path ./Install-NewRelicMSSQLAgent.ps1 -Value (Get-Content ./Install-NewRelicMSSQLAgent.ps1).Replace("<Environment>","$Envt")
Set-Content -Path ./Install-NewRelicMSSQLAgent.ps1 -Value (Get-Content ./Install-NewRelicMSSQLAgent.ps1).Replace("<namespace>","$vault_namespace")
Set-Content -Path ./Install-NewRelicMSSQLAgent.ps1 -Value (Get-Content ./Install-NewRelicMSSQLAgent.ps1).Replace("<awsregion>","$awsRegion")
./Install-NewRelicMSSQLAgent.ps1

Set-Location $dPath
Set-Content -Path ./Rotate-NewRelicTokens.ps1 -Value (Get-Content ./Rotate-NewRelicTokens.ps1).Replace("<SQLPort>","$SQLPort")
Set-Content -Path ./Rotate-NewRelicTokens.ps1 -Value (Get-Content ./Rotate-NewRelicTokens.ps1).Replace("<Environment>","$Envt")
Set-Content -Path ./Rotate-NewRelicTokens.ps1 -Value (Get-Content ./Rotate-NewRelicTokens.ps1).Replace("<namespace>","$vault_namespace")
Set-Content -Path ./Rotate-NewRelicTokens.ps1 -Value (Get-Content ./Rotate-NewRelicTokens.ps1).Replace("<awsregion>","$awsRegion")

Write-Host "Creating RotateToken SQL Agent job..."
Invoke-Sqlcmd -Database msdb -InputFile "$mssqlScriptsFolder\RotateTokenSQLAgentJob.sql" -QueryTimeout 30;

Write-Output (">>>>>>>>>> Completed install_NewRelic at: $(Get-Date -format 'u') >>>>>>>>>>") | Out-File -Append $logFile
