# Create the function to set the windows service account name and password used for the SQL Server services, the service name is passed to parameter $SVCName
function global:Set-SQLSvcAcct {
	$SvcAcctName = $($args[0])
	$SVCName = $($args[1])
	$SvcAcctPWD = $($args[2])
	$WindowsServerToUpdate= $env:COMPUTERNAME

	#Load the SqlWmiManagement assembly
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
	$wmi = new-object ("Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer") $WindowsServerToUpdate

	$Services = $wmi.services | where {($_.name -eq $SVCName) }
	ForEach($Service in $Services)
	{
		$Service.SetServiceAccount($SvcAcctName, $SvcAcctPWD)
		$Service.Refresh()
	}

	# Start the service
	Start-Service -Name $SVCName

	# Return the account info after the update was done
	write-output (Format-LogMessage('This is the value after the update:'))
	$SMOWmiserver.Services | select name, type, ServiceAccount, DisplayName, Properties, StartMode, StartupParameters | where {$_.name -eq "$SVCName"} | Format-List
}
