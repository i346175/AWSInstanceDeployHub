function global:Set-SqlPort {

	$sqlPort = $($args[0])

	Write-Output (Format-LogMessage("Started setting SQL Custom Port to [$sqlPort] at: $(Get-Date -format 'u')")) | Out-File -Append $logFile

	[system.reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
	[system.reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null

	$mc = new-object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $env:COMPUTERNAME
	$Instance = $mc.ServerInstances['MSSQLSERVER']

	$protocol = $Instance.ServerProtocols['Tcp']
	$ip = $protocol.IPAddresses['IPAll']
	$ip.IPAddressProperties['TcpDynamicPorts'].Value = ''
	$ipProps = $ip.IPAddressProperties['TcpPort']
	#if it's already set, just boot...
	if($ipProps.Value -eq [string]$sqlPort){
		return;
	}
	$ipProps.Value = [string]$sqlPort
	$protocol.Alter()

	Write-Output (Format-LogMessage("Completed setting SQL Custom Port to [$sqlPort] at: $(Get-Date -format 'u')")) | Out-File -Append $logFile

	Write-Output (Format-LogMessage("Started restarting SQL services at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
	Restart-Service -Name "MSSQLSERVER" -Force
	Restart-Service -Name "SQLSERVERAGENT" -Force
	Write-Output (Format-LogMessage("Completed restarting SQL services at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
}
