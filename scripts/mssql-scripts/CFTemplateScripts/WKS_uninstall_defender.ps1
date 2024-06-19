try { 

    if ( $(Get-WindowsFeature -Name Windows-Defender).Installed) {
 
        Uninstall-WindowsFeature -Name Windows-Defender -Confirm:$false -Remove 

        Write-Host "Windows Defender Uninstalled" 

    } else { 

        Write-Host "Windows Defender is not installed" 

    } 

} catch { 

    Write-Error "Windows Defender Uninstallation failed" 

} 
