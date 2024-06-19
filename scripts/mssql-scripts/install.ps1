<# Catalyst Agent for Windows version 0.9 #>
# Coding framework for ps1.  Organize all executions as functions for better code organization and refactoring ability.
# Start with Main function declaration, then all helper function declarations.
# Last, calling Main function and the end.
#

function Main {
    # Set-CatalystEnv needs catalyst-env.ps1 to set environment parameters.

    try {
        Set-CatalystEnv
        Load-Functions
        Load-CatalystModule
        # invoke fn received from automation api
        Write-Output (Format-LogMessage(">>>>>>>>>>>> Invoke-Expression [install-mssql]")) | Out-File -Append $logFile
        Invoke-Expression "install-mssql"
        Write-Output (Format-LogMessage("<<<<<<<<<<<< Done Invoke-Expression [install-mssql]")) | Out-File -Append $logFile
    } catch {
        Write-Output (Format-LogMessage(">>>>>>>>>>>> Install Exception!!! >>>>>>>>>>>>>>>>>>>>")) | Out-File -Append $logFile
        Write-Output (Format-LogMessage("Exceptions caught: $_")) | Out-File -Append $logFile
        Write-Output (Format-LogMessage("<<<<<<<<<<<<<<<< Install Abort!!! <<<<<<<<<<<<<<<<<<<<<")) | Out-File -Append $logFile
        $exitCode = 1
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
}

function Set-CatalystEnv {
    try {
        $Global:mssqlScriptsFolder="C:\mssql-scripts"
        & $mssqlScriptsFolder\send_logs.ps1
        $Global:logsFolder = "$mssqlScriptsFolder\install_logs"

        $timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
        $Global:logFile = "$logsFolder\install_log_$timestamp.log"

        If ((Test-Path $logsFolder) -eq $false) {
            New-Item -ItemType "directory" -Path $logsFolder
        }

        $TimeNow = Get-Date

        Write-Output (Format-LogMessage("Windows Install ran at $TimeNow")) | Out-File -Append $logFile
    } catch {
        (Format-LogMessage($_ | Out-String)) | fl -Force | Out-File -Append $logFile
        throw "Set-Environment failed.  See $logFile for details."
    }

}

function Load-Functions {
    try {
        Write-Output (Format-LogMessage("Loading functions")) | Out-File -Append $logFile
        & $mssqlScriptsFolder\functions.ps1
        Write-Output (Format-LogMessage("Successfully loaded functions")) | Out-File -Append $logFile
    } catch {
        (Format-LogMessage($_ | Out-String)) | fl -Force | Out-File -Append $logFile
        throw "Load-Functions failed.  See $logFile for details."
    }
}

function Load-CatalystModule {
    try {
        #load the functions in main.ps1 here
        Write-Output (Format-LogMessage("loading functions from $mssqlScriptsFolder\main.ps1 now...")) | Out-File -Append $logFile
        & $mssqlScriptsFolder\main.ps1
        # load env variables
        & $mssqlScriptsFolder\mssql_environment_loader.ps1
        # load set sql accoiunts
        & $mssqlScriptsFolder\set_service_account.ps1
        Write-Output (Format-LogMessage("Functions from $mssqlScriptsFolder\main.ps1 loaded...")) | Out-File -Append $logFile
    } catch {
        Write-Output (Format-LogMessage("Failed to load functions from $mssqlScriptsFolder\main.ps1. Error: $_")) | Out-File -Append $logFile
        throw "$_ See $logFile for details."
    }
}

Main


