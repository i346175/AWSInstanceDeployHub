
function Main {
	$counter = 0
	$sleepTime = 30
	$iterations = 60
	Write-Output ("Iteration [$counter] of checking cluster creation and sql cert") | Out-File -Append $logFile
	$certInstalled =  Invoke-sqlcmd -ServerInstance "$env:COMPUTERNAME" -Database "master" -Query "SELECT name FROM sys.certificates WHERE name='$env:COMPUTERNAME-Cert'" -QueryTimeout 10 -TrustServerCertificate
	while (!$certInstalled -and $counter -lt $iterations) {
		$counter++
		Start-Sleep -s $sleepTime
		Write-Output ("Iteration [$counter] of checking cluster creation and sql cert") | Out-File -Append $logFile
		$certInstalled =  Invoke-sqlcmd -ServerInstance "$env:COMPUTERNAME" -Database "master" -Query "SELECT name FROM sys.certificates WHERE name='$env:COMPUTERNAME-Cert'" -QueryTimeout 10 -TrustServerCertificate
	}
	$clusterCreated = Get-Cluster
	if($clusterCreated) {
		try {
			Write-Output ("Running on Node [$env:COMPUTERNAME!") | Out-File -Append $logFile
			Write-Output (">>>>>>>>>>>> Started Enable HADR configuration at: $(Get-Date -format 'u') >>>>>>>>>>>>") | Out-File -Append $logFile
			Enable-Hadr
			Check-HadrEnabled
			Write-Output ("<<<<<<<<<<<< Completed Enable HADR configuration at: $(Get-Date -format 'u') <<<<<<<<<<<<") | Out-File -Append $logFile
		} catch {
			Write-Output (">>>>>>>>>>>> Enable HADR Exception!!! >>>>>>>>>>>>>>>>>>>>") | Out-File -Append $logFile
			Write-Output ("Exceptions caught: $_") | Out-File -Append $logFile
			Write-Output ("<<<<<<<<<<<<<<<< Enable HADR Abort!!! <<<<<<<<<<<<<<<<<<<<<") | Out-File -Append $logFile
		}
	}
}


function global:Enable-Hadr {
	try {
		Write-Output ("Started enabling HADR setting at: $(Get-Date -format 'u')") | Out-File -Append $logFile
		[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
		$srv = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $env:COMPUTERNAME
		$service = $srv.Services | Where-Object{$_.Name -eq 'MSSQLSERVER'}
		$service.ChangeHadrServiceSetting($true);
		Write-Output ("Started restarting SQL services at: $(Get-Date -format 'u')") | Out-File -Append $logFile
		Get-Service -Name MSSQLSERVER | Restart-Service -Force
		Get-Service -Name SQLSERVERAGENT | Start-Service
		Write-Output ("Completed restarting SQL services at: $(Get-Date -format 'u')") | Out-File -Append $logFile
		Write-Output ("Completed enabling HADR setting at: $(Get-Date -format 'u')") | Out-File -Append $logFile
	} catch {
		($_) | fl -Force | Out-File -Append $logFile
		throw "Enable-Hadr function Error! See $logFile for details"
	}
}


function global:Check-HadrEnabled {
	try {
		Write-Output ("Started checking HADR setting at: $(Get-Date -format 'u')") | Out-File -Append $logFile
		[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
		$srv = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $env:COMPUTERNAME
		$service = $srv.Services | Where-Object{$_.Name -eq 'MSSQLSERVER'}
		if ($service.IsHadrEnabled -eq $true) {
			Write-Output ("HADR setting is enabled on node [$env:COMPUTERNAME]!") | Out-File -Append $logFile
		} else {
			throw "Hadr setting is not enabled on node [$env:COMPUTERNAME]!"
		}
		Write-Output ("Completed checking HADR setting at: $(Get-Date -format 'u')") | Out-File -Append $logFile
	} catch {
		($_) | fl -Force | Out-File -Append $logFile
		throw "Check-HadrEnabled function Error! See $logFile for details"
	}
}

Main 
