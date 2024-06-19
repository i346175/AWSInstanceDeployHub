<# Configure SQL Server #>
# Coding framework for ps1.  Organize all executions as functions for better code organization and refactoring ability.
# Start with Main function declaration, then all helper function declarations.
# Last, calling Main function and the end.
#
function Main {
    $exitCode = 1
    try {
        Set-Environment
        Load-Functions
        Write-Output (Format-LogMessage(">>>>>>>>>>>> Started MSSQL Configuration at: $(Get-Date -format 'u') >>>>>>>>>>>>")) | Out-File -Append $logFile
        Set-SqlPort $CustomSqlPort
        Write-Output (Format-LogMessage("<<<<<<<<<<<< Completed MSSQL Configuration at: $(Get-Date -format 'u') <<<<<<<<<<<<")) | Out-File -Append $logFile
        $exitCode = 0
    } catch {
        Write-Output (Format-LogMessage(">>>>>>>>>>>> MSSQL Configuration Exception!!! >>>>>>>>>>>>>>>>>>>>")) | Out-File -Append $logFile
        Write-Output (Format-LogMessage("Exceptions caught: $_")) | Out-File -Append $logFile
        Write-Output (Format-LogMessage("<<<<<<<<<<<<<<<< MSSQL Configuration Abort!!! <<<<<<<<<<<<<<<<<<<<<")) | Out-File -Append $logFile
    }
    $resourceToSignal=''
    if ($TemplateType -eq "ClusterTemplate") {
        $resourceToSignal = 'MssqlServerInstallWaitCondition'
    } elseif ($TemplateType -eq "AddNodeTemplate") {
        $resourceToSignal = 'MssqlAddServerInstallWaitCondition'
    } elseif ($TemplateType -eq "SingleInstanceTemplate") {
        $resourceToSignal = 'Master'
    }
    $ProxyVar = $env:https_proxy
    $env:https_proxy = ''
    cfn-signal.exe -e $exitCode --region $Region --resource $resourceToSignal --stack $StackName
    $env:https_proxy = $ProxyVar
}

function Set-Environment {
    try {
        $Global:mssqlScriptsFolder="C:\mssql-scripts"
        & $mssqlScriptsFolder\send_logs.ps1
        $Global:logsFolder = "$mssqlScriptsFolder\configuration_logs"
        $timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
        $Global:logFile = "$logsFolder\configuration_log_$timestamp.log"
        If ((Test-Path $logsFolder) -eq $false) {
            New-Item -ItemType "directory" -Path $logsFolder
        }

        $TimeNow = Get-Date
        Write-Output (Format-LogMessage("MSSQL Configurator ran at $TimeNow")) | Out-File -Append $logFile
    } catch {
        Write-Output (Format-LogMessage("Set-Environment failed.")) | Out-File -Append $logFile
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "See $logFile for details."
    }
}

function Load-Functions {
    try {
        Write-Output (Format-LogMessage("Loading functions from $mssqlScriptsFolder\set_mssql_port.ps1 now...")) | Out-File -Append $logFile
        & $mssqlScriptsFolder\set_mssql_port.ps1
        Write-Output (Format-LogMessage("Functions from $mssqlScriptsFolder\set_mssql_port.ps1 loaded...")) | Out-File -Append $logFile
    } catch {
        Write-Output (Format-LogMessage("Failed to load functions from $mssqlScriptsFolder\set_mssql_port.ps1")) | Out-File -Append $logFile
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "See $logFile for details."
    }
}

Main
