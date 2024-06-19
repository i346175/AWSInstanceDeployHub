param(
    [parameter(Mandatory=$true)][string]$Domain,
    [parameter(Mandatory=$true)][string]$templateAMI,
    [parameter(Mandatory=$true)][string]$ConfigType
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

$InstanceName = $env:ComputerName
log "Service Validation Started."
$services = Get-Content "c:\mssql-scripts\serverCompliance\services.json" -raw | ConvertFrom-Json
foreach($s in $services.services)
    {
    if(($s.name -match "McAfee") -and ($Domain -notmatch "USPSCC")){Continue}
    if(($s.name -match "Trend Micro Deep Security Agent") -and ($Domain -match "USPSCC")){Continue}
    
    #Check for New Relic service, and skip if server has TAG "TESTING-NO-MONITORING" or "TESTING-NO-MONITORING-DRS"
    if(($s.name -match "New Relic") -and ($ConfigType -in ("TESTING-NO-MONITORING","TESTING-NO-MONITORING-DRS"))){Continue}
    
    $serviceStatus = & "c:\mssql-scripts\serverCompliance\validate-service.ps1" "$($s.name)" "$($s.Executable)"
    if($serviceStatus){
        $s.Status = "Compliant"
    }
    else{
        $s.Status = "Non-Compliant"
    }
    }
$services | ConvertTo-Json | Out-File "c:\mssql-scripts\serverCompliance\services.json"


<# SKIP AMI check. Ref: CSCI-6333
if($Domain -notmatch "USPSCC"){
    $imageResults = & "c:\mssql-scripts\serverCompliance\validate-GoldenImage.ps1" "$($templateAMI)"
    }
#>
<#
# There's currently no checks for registry keys required, but for vulnerability validation purposes, this functionality was written. 
# M.R. 1/25/2023
#
#$ExampleRegKey = "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\"
#$ExampleRegName = "ProxyServer"
#$desiredValue = "http://proxy.service.cnqr.tech:3128"

$services = Get-Content "c:\mssql-scripts\serverCompliance\services.json" -raw | ConvertFrom-Json
foreach($r in $services.registry){
    $regResults = & "c:\mssql-scripts\serverCompliance\validate-registrykey.ps1" "$($r.regKey)" "$($r.regName)" "$($r.desiredValue)"
}
if ($regResults){
    log "The sought registry key was found, and correctly set."
    log "Key Sought: $ExampleRegKey"
}
else{
    log "The registry key was either not found, or did not match desired value. Server is Non-Compliant."
}
#>

log "Completed validation checks. Examining Results."
<# SKIP AMI check. Ref: CSCI-6333
Start-Sleep -Seconds 60
if($imageResults)
{
    log "Image Compliance Passed. ($instancename) is using the latest AMI."
}
else {
    if($Domain -match "USPSCC"){
        log "Image Compliance Check not currently available in PSCC."
    }
    else{
        log "Image Compliance Failed. This machine is not using the latest AMI."
    }
}
#>
$serviceValidation = Get-Content "c:\mssql-scripts\serverCompliance\services.json" -raw | ConvertFrom-Json
#[bool]$compliantState
foreach($s in $serviceValidation.services)
{
    #if $status is not set, then check was skipped
    if(!$s.status -and $s.name -match "New Relic"){
        log "Service $($s.name) compliance check is skipped if server has TAG 'TESTING-NO-MONITORING' or 'TESTING-NO-MONITORING-DRS'."
        continue
    }
    if($s.status -eq "Non-Compliant"){
        log "Service $($s.name) failed compliance check on ($InstanceName). This server is non-compliant."
        #$compliantState = $false
    }    
    else{
        log "Service $($s.name) is compliant."
    }
}
<#
#
# Leaving this code commented out, for now. Can't decide if having this check adds value, or not. 
# Might be more useful if it can be reported back to build script, instead of logged? 
#
if($compliantState){
    log "($InstanceName) has passed all compliance checks."
}
else{
    log "($InstanceName) has failed at least one compliance checks."
}#>
