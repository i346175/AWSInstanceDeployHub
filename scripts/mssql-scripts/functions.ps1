function global:Generate-RandomPassword {
    Write-Output (Format-LogMessage(">>>>>>>>>> Generate-RandomPassword >>>>>>>>>>")) | Out-File -Append $logFile
    $Assembly = Add-Type -AssemblyName System.Web
    $Global:SAPassword = [System.Web.Security.Membership]::GeneratePassword(32,0)
    $pStr = $SAPassword.Replace("'","''")
    Set-Content -Path C:\cfn\temp\saCred.ps1 -Value "`$Global:SAPassword = '$pStr'"
    Write-Output (Format-LogMessage("<<<<<<<<<< Generate-RandomPassword <<<<<<<<<<")) | Out-File -Append $logFile
}
<#
function global:Invoke-Orchestrator-Vault-Store {
    $data = $($args[0])
    <# HOW TO CALL THIS FUNCTION
        $jsonRequest = [ordered]@{
            MSSQLSERVER= @{
                user = "$MSSQLSERVER_user"
                password = "$pwd"
            }
            SQLSERVERAGENT = @{
                user = "$SQLSERVERAGENT_user"
                password = "$pwd"
            }
            "SA" = @{
                user = "$sa_user"
                password = "$pwd"
            }
        }
        $jsonRequest = $jsonRequest | ConvertTo-Json -Depth 10
        $resp = Invoke-Orchestrator-Vault-restore $jsonRequest
    #>
    <#
    try {
        Write-Output ">>>>>>>>>> Invoke-Orchestrator-Vault-Store >>>>>>>>>>"
        $resp = Invoke-RestMethod -SkipCertificateCheck -Body ([System.Text.Encoding]::UTF8.GetBytes($data)) -Uri $OrchestratorVaultURI -ContentType "application/json" -Method POST
        Write-Output "<< Completed storing secret for username: $userName <<"
        Write-Output "<<<<<<<<<< Invoke-Orchestrator-Vault-Store <<<<<<<<<<"
    } catch {
        $_ | fl -Force
    }
}


function global:Invoke-Orchestrator-Vault-Restore {
    try {
        $resp = Invoke-RestMethod -SkipCertificateCheck -Uri $OrchestratorVaultURI -ContentType "application/json" -Method GET
        return $resp
    } catch {
        (Format-LogMessage($_ ))| fl -Force
        throw "$_"
    }
}
#>