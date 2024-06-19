[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') *> $null
$installDate = (Get-WmiObject -Class Win32_OperatingSystem).InstallDate
$currentDate = Get-Date
$DateTimeInstallDate = [System.Management.ManagementDateTimeConverter]::ToDateTime($InstallDate)
$daysRemaining = (([datetime]$DateTimeInstallDate).AddDays(30) - $currentDate).Days
if ($daysRemaining -lt 0) {
   [System.Windows.Forms.MessageBox]::Show("New workstation build has issues. Please inform the DevOps team.") 
} 
elseif ($daysRemaining -le 5 ) {
   [System.Windows.Forms.MessageBox]::Show("The server will be decommission in $daysRemaining days. Please start saving your work!") 
}