Param(
    $thumbprint,
    $taskName = 'Notify Expired Cert',
    $vpc,
    $stack
)

$cert = Get-ChildItem -path Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq $thumbprint}

#Rare Case: If no cert skip notification 
if (!$cert) {
    return
}

#Store Cert in SQLServer
Import-Module SqlServer -DisableNameChecking -Force -WarningAction Ignore -ErrorAction SilentlyContinue | Out-Null

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