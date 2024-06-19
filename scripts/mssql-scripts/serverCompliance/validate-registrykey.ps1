[CmdletBinding()]
param (
	[parameter(Mandatory=$true)][string]$registryKeyPath,
    [parameter(Mandatory=$true)][string]$registryKeyName,
    [parameter(Mandatory=$true)][string]$desiredValue
)
function log() {
    param (
     [string]$string = "",
     [string]$color,
     [bool]$quiet = $false
      )
        $logstring = ($(Get-Date).toString())+" : "+$string
        if(! $quiet)
            {
             if($color)
                {
                 Write-Host $logstring -BackgroundColor $color
                }
             else
                {
                 Write-Host $logstring
                }
            }
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\validate_server_compliance.log"
}

log "Start $registryKeyPath Validation "
$keyExists = Get-ItemPropertyValue -Path $registryKeyPath -Name $registryKeyName -ErrorAction SilentlyContinue
if($keyExists -eq $desiredValue)
{
    log "Registry key is set correctly."
    return $true
}
else {
    if($keyExists)
    {
        log "Registry Key exists, but value set incorrectly."
        log "Value: $keyexists"
        return $false
    }
    log "Unable to find registry key desired."
    return $false
}
