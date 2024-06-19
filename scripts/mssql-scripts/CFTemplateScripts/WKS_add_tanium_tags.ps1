Write-Output (">>>>>>>>>> Starting creation of Tanium Tags at: $(Get-Date -format 'u') >>>>>>>>>>")

If(!(Test-Path -Path 'HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\')){


write-output ("<<<<<<<<<< Registry Path Not Present. Sleeping for 5 minutes. $(Get-Date -format 'u') <<<<<<<<<<")

start-sleep -seconds 300


}
If(!(Test-Path -Path 'HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\Tags')){


$PathCreated = New-Item -Path 'HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\Tags\'


write-output ("<<<<<<<<<< Created registry path for Tanium Tags at: $(Get-Date -format 'u') <<<<<<<<<<")

}
write-output "Sleep Timer initiated."

start-Sleep -seconds 15


$tagCreated = New-ItemProperty -Path 'HKLM:\Software\Wow6432Node\Tanium\Tanium Client\Sensor Data\Tags' -Name 'patch-schedule-weekly-Friday-noreboot'
if([bool]$tagCreated){
write-output ("<<<<<<<<<< Completed Tanium Tag Creation at: $(Get-Date -format 'u') <<<<<<<<<<")
}
else{


write-output ("<<<<<<<<<< Failed to create Tanium Tag. $(Get-Date -format 'u') <<<<<<<<<<")

}
write-output ("<<<<<<<<<< Completed enable_env_variable_for_proxy at: $(Get-Date -format 'u') <<<<<<<<<<")

write-output (">>>>>>>>>> Started Restart-Computer at: $(Get-Date -format 'u') >>>>>>>>>>" ) 
