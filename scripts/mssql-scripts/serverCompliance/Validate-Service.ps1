[CmdletBinding()]
param (
	[parameter(Mandatory=$true)][string]$ServiceName,
	[parameter(Mandatory=$true)][string]$ServiceExeName
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

#log " Start $ServiceName Validation "
$serviceStatus = (Get-Service -Name $ServiceExeName -ErrorAction SilentlyContinue).Status
if($serviceStatus -eq "Running")
{
    #log "$ServiceName Validation Complete"
    return $true
}
else {
    if($serviceStatus)
    {
     log "Service Not Functional. $ServiceName is $serviceStatus."
     #log "$ServiceName Validation Complete"
     return $false
    }
    log "$ServiceName is not installed."
    #log "$ServiceName Validation Complete"
    return $false
}
