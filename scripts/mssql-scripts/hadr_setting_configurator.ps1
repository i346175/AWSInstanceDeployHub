<# HADR Setting Configurator #>
# Coding framework for ps1.  Organize all executions as functions for better code organization and refactoring ability.
# Start with Main function declaration, then all helper function declarations.
# Last, calling Main function and the end.

function Main {
    Set-Environment
    & $mssqlScriptsFolder\enable_hadr.ps1
}

function Set-Environment {
    try {
        $Global:mssqlScriptsFolder="C:\mssql-scripts"
        & $mssqlScriptsFolder\send_logs.ps1
        $Global:logsFolder = "$mssqlScriptsFolder\cluster_build_logs"
        $timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
        $Global:logFile = "$logsFolder\enable_hadr_log_$timestamp.log"
        if ((Test-Path $logsFolder) -eq $false) {
            New-Item -ItemType "directory" -Path $logsFolder
        }

        $TimeNow = Get-Date
        Write-Output (Format-LogMessage("Enable HADR ran at $TimeNow")) | Out-File -Append $logFile
    } catch {
        Write-Output (Format-LogMessage("Set-Environment failed.")) | Out-File -Append $logFile
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "See $logFile for details."
    }
}


Main


