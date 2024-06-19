<# ========================================================================================================================
Description: Script validates the latest Golden Image being used for server compliance.
======================================================================================================================== #>

param (
	[parameter(Mandatory=$true)][string]$templateAMI
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

log "Starting Golden Image Validation."

$latestAMI = (Get-SSMParameter -Name /concur-console-image-factory/dba/dbsqlAMI/Win2019 -WithDecryption $true).Value

if ($templateAMI -eq $latestAMI){ 
	#log "This server ($InstanceName) is compliant."
	log "It is currently using the latest golden image - $latestAMI."
    return $true
} 
else {
	#log "This server ($InstanceName) is non-compliant."
	log "It is currently using an outdated golden image - $templateAMI."
	log "Please use the latest golden image - $latestAMI."
    return $false
	#$nonCompliantSvc.Add("Golden Image")
}
log "Golden Image Validation Completed."
