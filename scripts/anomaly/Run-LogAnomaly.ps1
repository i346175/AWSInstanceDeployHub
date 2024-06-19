Set-Location $PSScriptRoot

. ./Log-Anomaly.ps1
. ./Log-Event.ps1
. ./Update-TaskTime.ps1

Log-Anomaly -ErrorAction Stop | Out-String | Log-Event -EventSource "LogAnomaly"
Update-TaskTime  -ErrorAction Stop | Out-String | Log-Event -EventSource "UpdateTaskTime"