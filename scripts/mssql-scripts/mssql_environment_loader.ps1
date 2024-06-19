<#

# MSSQL Environment Loader
# version 0.0
 
# Implementation Guidelines:
#
# Coding framework for ps1
# Organize all executions as functions for better code organization and refactoring ability
# Start with Main function declaration, then all helper function declarations.
# Last, calling Main function and the end.

#>

function Main {
    try {
        Load-MSSQLEnvironment
        Load-ConfigSettings
    } catch {
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "MSSQL Environment Loader Error! See $logFile for details"
    }
}

# Setup variables needed for sql base install operation
function Load-MSSQLEnvironment {    
    $SQLVers = "<sqlversion>".Split('_')[0].ToString().ToLower()
    write-output (Format-LogMessage(">>>>>>>>>> Started loading MSSQL environment variables at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
    $Global:domain = $env:USERDOMAIN
    $Global:RoleAdminGroup= "$domain\$roletype" + "_admins"
    $Global:SQLSetupINIFile="$mssqlScriptsFolder\$($SQLVers)InstallConfigFile_DomainBacked.ini"
    write-output (Format-LogMessage("<<<<<<<<<< Completed loading MSSQL environment variables at: $(Get-Date -format 'u') <<<<<<<<<<" ))| Out-File -Append $logFile
}

# Load configuration settings
function Load-ConfigSettings {
    write-output (Format-LogMessage(">>>>>>>>>> Started loading configuration settings at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
    & $mssqlScriptsFolder\settings.ps1
    write-output (Format-LogMessage("<<<<<<<<<< Completed loading configuration settings at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

Main