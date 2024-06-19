 Param(
    $thumbprint,
    $taskName = 'Notify Expired Cert',
    $vpc,
    $stack
)

#Store Cert in SQLServer
Import-Module SqlServer -DisableNameChecking -Force -WarningAction Ignore -ErrorAction SilentlyContinue | Out-Null

$sqlQuery = "
DECLARE @lastReboot DATETIME;
SELECT @lastReboot = sqlserver_start_time FROM sys.dm_os_sys_info;
CREATE TABLE #Loglist (id INT, LogDate DATETIME, size INT);
INSERT INTO #Loglist
EXEC sys.sp_enumerrorlogs;

DECLARE @LogID int
SELECT TOP 1 @LogID=id from #Loglist WHERE LogDate <= @lastReboot ORDER BY id;
SET @LogID = @LogID-1;
DROP TABLE #loglist;

CREATE TABLE #Cert (LogDate DATETIME, ProcessInfo VARCHAR(50), [Certificate] VARCHAR(1000))
INSERT INTO #Cert
EXEC sp_readerrorlog @LogID,1, N'Cert Hash'
    
SELECT REPLACE(REPLACE([Certificate],'The certificate [Cert Hash(sha1) `"',''),'`"] was successfully loaded for encryption.','') AS SQLThumbPrint FROM #Cert
DROP TABLE #Cert"

try {
    $thumbprint = (Invoke-Sqlcmd -Database master -Query $sqlQuery -TrustServerCertificate).sqlThumbPrint
}
catch {
    $thumbprint = (Invoke-Sqlcmd -Database master -Query $sqlQuery).sqlThumbPrint
}

$cert = Get-ChildItem -path Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq $thumbprint}

#Rare Case: If no cert skip notification 
if (!$cert) {
    return
}

#Store Cert in SQLServer
$sqlQuery = "
IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE name = 'sqlCertThumbPrint')
EXEC sp_addextendedproperty @name = N'sqlCertThumbPrint' ,@value = N'$($thumbprint)';
ELSE
EXEC sp_updateextendedproperty @name = N'sqlCertThumbPrint' ,@value = N'$($thumbprint)';
"

try {
    Invoke-Sqlcmd -Database master -Query $sqlQuery -TrustServerCertificate 
}
catch {
    Invoke-Sqlcmd -Database master -Query $sqlQuery
}
##Regenerate Task

#Remove Task
$getTask  = Get-ScheduledTask | Where-Object {$_.TaskName -eq $taskName } -ErrorAction Stop
  
if ($getTask){
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $getTask.TaskPath -Confirm:$false -ErrorAction Stop
}

#Add Task
$startTime = $cert.NotAfter 
$actions = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "D:\PowershellScripts\certNotification\Notify-CertExpired.ps1 -Thumbprint '$($thumbprint)' -ExpiryDate '$($startTime)' -VPC '$($vpc)' -Stack '$($stack)'" -ErrorAction Stop
$trigger = New-ScheduledTaskTrigger -Once -At $startTime -ErrorAction Stop
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -ErrorAction Stop -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest -ErrorAction Stop
$task = New-ScheduledTask -Action $actions -Trigger $trigger -Settings $settings -Principal $principal -ErrorAction Stop
  
Register-ScheduledTask -TaskName $taskName -InputObject $task -User "System" -ErrorAction Stop | Out-Null

#Start Task if Already Expired
if ((Get-Date) -ge $startTime) {
Start-ScheduledTask -TaskName $taskName
}  
