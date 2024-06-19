<#
 
# MSSQL Downloader
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
        write-output (Format-LogMessage(">>>>>>>>>> Started download and extraction of MSSQL installer artifact at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
        # Setup
        Set-MSSQLDownloadEnv
        # Download
        Get-Artifact
        # Extract
        Extract-Artifact
        # Copy
        Copy-FilesToInstallerDir
        # Teardown
        Destroy-MSSQLDownloadEnv
        write-output (Format-LogMessage("<<<<<<<<<< Completed download and extraction of MSSQL installer artifact at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
    } catch {
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "MSSQL Downloader Error! See $logFile for details"
    }

}

function Set-MSSQLDownloadEnv {
    # initialize variables
    . C:\cfn\temp\CFN_Variables.ps1
    $Global:SQLInstallerDir = "$mssqlScriptsFolder\sql_installer"
    $Global:SQLInstallerTempDir = "$mssqlScriptsFolder\sql_installer_temp"
    $Global:SQLInstallerArtifact = "<sqlversion>.zip"
    $Global:SQLInstallerExtractedDir = "<sqlversion>".Split('_')[0]
    #$Global:DotNetSource = "C:\iso_sxs\sxs"
    # Get the domain
    $domainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
    if ($domainName -eq "integration.system.cnqr.tech" -and $StackName -notlike "TestSQLLM*" -and $StackName -notlike "*PIM*") { 
        # Integration environment to ALWAYS use DEV Edition of SQL Server
        $Global:SQLInstallerArtifact = "$($SQLInstallerExtractedDir)_Dev.zip"
    }

    $envt = $domainname.Split(".")[0]
    $Global:DownloadURL =  "s3://" + $envt + "-dbsql-rpl/AWSInstanceDeployHub/"

    #$Global:DotNetInstaller = "microsoft-windows-netfx3-ondemand-package.cab"
    # Make final installer dir
    Write-Output (Format-LogMessage(">>>>>>>>>> Started creation of SQL Installer dir: $SQLInstallerDir at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
    if (Test-Path $SQLInstallerDir) {
        Format-LogMessage( Remove-Item $SQLInstallerDir -Recurse -Force ) | Out-File -Append $logFile
    }

    Format-LogMessage( New-Item $SQLInstallerDir -type directory -force ) | Out-File -Append $logFile
    Write-Output (Format-LogMessage("<<<<<<<<<< Completed creation of SQL Installer dir: $SQLInstallerDir at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile

    # Make temp dir
    Write-Output (Format-LogMessage(">>>>>>>>>> Started creation of temp directory: $SQLInstallerTempDir at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
    if (Test-Path $SQLInstallerTempDir){
        Format-LogMessage( Remove-Item $SQLInstallerTempDir -Recurse -Force ) | Out-File -Append $logFile
    }
    Format-LogMessage( New-Item $SQLInstallerTempDir -type directory -force ) | Out-File -Append $logFile

    #Write-Output (Format-LogMessage(">>>>>>>>>> Started creation of DotNet source directory: $DotNetSource at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
    #if( Test-Path $DotNetSource) {
    #    Format-LogMessage( Remove-Item $DotNetSource -Recurse -Force ) | Out-File -Append $logFile
    #}
    #Format-LogMessage( New-Item $DotNetSource -type directory -force ) | Out-File -Append $logFile

    Write-Output (Format-LogMessage("<<<<<<<<<< Completed creation of temp directory: $SQLInstallerTempDir at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

Function Get-Artifact {
    Write-Output (Format-LogMessage(">>>>>>>>>> Started execution of Get-Artifact to download MSSQL installer artifact at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
    Write-Output (Format-LogMessage("########## Download: $SQLInstallerArtifact from: $DownloadURL ##########")) | Out-File -Append $logFile
    # $Client = New-Object System.Net.WebClient
    $Artifact = "$DownloadURL$SQLInstallerArtifact"
    $ArtifactDownloadPath = "$SQLInstallerTempDir\$SQLInstallerArtifact"
    aws s3 cp $Artifact $ArtifactDownloadPath --no-progress
    # $Client.DownloadFile($Artifact, $ArtifactDownloadPath)
    
    #Write-Output (Format-LogMessage("########## Download: $DotNetInstaller from: $DownloadURL ##########")) | Out-File -Append $logFile
    #$Artifact = "$DownloadURL$DotNetInstaller"
    #$ArtifactDownloadPath = "$DotNetSource\$DotNetInstaller"
    #aws s3 cp $Artifact $ArtifactDownloadPath --no-progress
    ## $Client.DownloadFile($Artifact, $ArtifactDownloadPath)
    ## $Client.Dispose()
    #Write-Output (Format-LogMessage("<<<<<<<<<< Completed execution of Get-Artifact to download MSSQL installer artifact at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

Function Extract-Artifact {
    Write-Output (Format-LogMessage(">>>>>>>>>> Started execution of Extract-Artifact at: $(Get-Date -format 'u') >>>>>>>>>>" ))| Out-File -Append $logFile
    $Source = "$SQLInstallerTempDir\$SQLInstallerArtifact"
    $Destination = $SQLInstallerTempDir
    write-output (Format-LogMessage("########## Extracting from: $Source to: $Destination ##########")) | Out-File -Append $logFile
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Source, $Destination)
    Write-Output (Format-LogMessage("<<<<<<<<<< Completed execution of Extract-Artifact at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

Function Copy-FilesToInstallerDir {
    Write-Output (Format-LogMessage(">>>>>>>>>> Started execution of Copy-FilesToInstallerDir to copy artifact from: $SQLInstallerTempDir to: $SQLInstallerDir at: $(Get-Date -format 'u') >>>>>>>>>>")) | Out-File -Append $logFile
    $Source = "$SQLInstallerTempDir\$SQLInstallerExtractedDir"
    $Destination = "$SQLInstallerDir\"
    $SQLVersNumber = $SQLInstallerExtractedDir.Replace('SQL','')
    write-output (Format-LogMessage("########## Copy folder from: $Source to: $Destination ##########" ))| Out-File -Append $logFile
    Copy-Item "$Source" -Destination "$Destination" -Force -Recurse
    $SQLPatchesArtifact = "$($DownloadURL)Updates/"
    Remove-Item -Path "$SQLInstallerDir\$SQLInstallerExtractedDir\Updates\*.exe" -Force
    aws s3 cp $SQLPatchesArtifact "$SQLInstallerDir\$SQLInstallerExtractedDir\Updates\" --recursive --no-progress --exclude "*" --include "SQLServer$($SQLVersNumber)*.exe" --no-progress
    Write-Output (Format-LogMessage("<<<<<<<<<< Completed execution of Copy-FilesToInstallerDir to copy artifact from: $SQLInstallerTempDir to: $SQLInstallerDir at: $(Get-Date -format 'u') <<<<<<<<<<")) | Out-File -Append $logFile
}

function Destroy-MSSQLDownloadEnv {
    # Destroy temp dir
    Write-Output (Format-LogMessage(">>>>>>>>>> Started removing temp folder: $SQLInstallerTempDir at: $( Get-Date -format 'u' ) >>>>>>>>>>")) | Out-File -Append $logFile
    if (Test-Path $SQLInstallerTempDir) {
        Remove-Item $SQLInstallerTempDir -Recurse -Force -ErrorAction Continue | Out-File -Append $logFile
    }
    Write-Output (Format-LogMessage("<<<<<<<<<< Completed removing temp folder: $SQLInstallerTempDir at: $( Get-Date -format 'u' ) <<<<<<<<<<")) | Out-File -Append $logFile
}


Main