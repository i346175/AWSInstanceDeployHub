<#

# MSSQL Server Installer
# version 0.0

# Implementation Guidelines:
#
# Coding framework for ps1
# Organize all executions as functions for better code organization and refactoring ability
# Start with Main function declaration, then all helper function declarations.
# Last, calling Main function and the end.

#>

function Main {
	try {
		write-output (Format-LogMessage(">>>>>>>>>> Started installation of MS SQL Server at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
		#Install-DotNetFramework
		Set-SQLIniAdminGroup
		Set-SQLSysAdminSAAccount
		Generate-RandomPassword
		Run-SQLServerExecutable
		$secrets = & "C:\mssql-scripts\get_secrets.ps1"
		$mssqlServerSecrets = $secrets.MSSQLSERVER
		$sqlAgentSecrets = $secrets.SQLSERVERAGENT
		Set-SQLSVCAccount $mssqlServerSecrets
		Set-SQLAgentAccount $sqlAgentSecrets
		write-output (Format-LogMessage("<<<<<<<<<< Completed installation of MS SQL Server at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
	} catch {
		(Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
		throw "MSSQL Server Installer Error! See $logFile for details"
	}
}

#function Install-DotNetFramework {
#	write-output (Format-LogMessage(">>>>>>>>>> Started execution of Install-DotNetFramework at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
#	$SourceInstallDir = "c:\iso_sxs\sxs"
#	write-output (Format-LogMessage(">>>>>>>>>> Using .Net source folder: $SourceInstallDir >>>>>>>>>>")) | Out-File -Append $logFile
#	$ExecResult = (Install-WindowsFeature Net-Framework-Core -source "$SourceInstallDir" *>&1)
#	(Format-LogMessage($ExecResult)) | Out-File -Append $logFile
#	write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Install-DotNetFramework at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
#}

# Update the .ini file to set the group name added as SA from $RoleAdminGroup
function Set-SQLIniAdminGroup {
	write-output (Format-LogMessage(">>>>>>>>>> Started execution of Set-SQLIniAdminGroup at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
	write-output (Format-LogMessage(">>>>>>>>>> Setting the initial SQL Admins group to: $RoleAdminGroup >>>>>>>>>>")) | Out-File -Append $logFile
	# build the string for the .ini file full path
	$FileToUpdate = "$SQLSetupINIFile"
	$SearchValue = 'DOMAIN\GROUP'
	# Set the group name in the .ini file
	(Get-Content $FileToUpdate).replace($SearchValue, $RoleAdminGroup) | Set-Content $FileToUpdate
	write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Set-SQLINIAdminGroup at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

# Update the .ini file to set up the sa_dba_prov as SA
function Set-SQLSysAdminSAAccount {
	$SqlSysAdminSAAccount = "$env:userdomain\sa_dba_prov"
	write-output (Format-LogMessage(">>>>>>>>>> Started execution of Set-SQLSysAdminSAAccount at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
	write-output (Format-LogMessage(">>>>>>>>>> Setting the initial SQL Sys Admin SA account to: $SqlSysAdminSAAccount >>>>>>>>>>")) | Out-File -Append $logFile
	# build the string for the .ini file full path
	$FileToUpdate = "$SQLSetupINIFile"
	$SearchValue = 'DOMAIN\dbaProvServiceAccount'
	# Set the group name in the .ini file
	(Get-Content $FileToUpdate).replace($SearchValue, $SqlSysAdminSAAccount) | Set-Content $FileToUpdate
	write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Set-SQLSysAdminSAAccount at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

function Run-SQLServerExecutable {
	write-output (Format-LogMessage(">>>>>>>>>> Started execution of Run-SQLServerExecutable at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile

	# Paramters for the SQL Server Executable
	$paramString = "/SAPWD=$SAPassword /ConfigurationFile=$SQLSetupINIFile"
	#Start the SQL commandline install using the .ini file name passed into the function
	$ExecResults = (Start-Process -FilePath "$SQLInstallerDir\$SQLInstallerExtractedDir\setup.exe" -Wait -ArgumentList "$paramString" *>&1 )
	Format-LogMessage($ExecResult) | Out-File -Append $logFile
	write-output (Format-LogMessage("<<<<<<<<<< Completed execution of Run-SQLServerExecutable at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

function Set-SQLSVCAccount {
	write-output (Format-LogMessage("#### Start Set MSSQLSERVER service account at: $(Get-Date -format 'u') ####" ))| Out-File -Append $logFile
	$secrets = $($args[0])
	$SQLSVCName = "MSSQLSERVER"
	$username = $secrets.user
	$domain = $env:USERDOMAIN
	$SvcAcctName = "$domain\$username"
	$SvcAcctPWD =  $secrets.password
	$ExecResults = Set-SQLSvcAcct $SvcAcctName $SQLSVCName $SvcAcctPWD
	Format-LogMessage($ExecResults)
	write-output (Format-LogMessage("#### End Set MSSQLSERVER service account at: $(Get-Date -format 'u') ####")) | Out-File -Append $logFile
}

function Set-SQLAgentAccount {
	write-output (Format-LogMessage("#### Start Set SQLSERVERAGENT service account at: $(Get-Date -format 'u') ####")) | Out-File -Append $logFile
	$secrets = $($args[0])
	$SQLSVCName = "SQLSERVERAGENT"
	$username = $secrets.user

	$domain = $env:USERDOMAIN
	$SvcAcctName = "$domain\$username"
	$SvcAcctPWD =  $secrets.password
	$ExecResults = Set-SQLSvcAcct $SvcAcctName $SQLSVCName $SvcAcctPWD
	Format-LogMessage($ExecResults)
	write-output (Format-LogMessage("#### End Set SQLSERVERAGENT service account at: $(Get-Date -format 'u') ####")) | Out-File -Append $logFile
}

Main
