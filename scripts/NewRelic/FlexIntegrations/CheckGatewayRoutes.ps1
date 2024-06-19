<# =================================================================================================================================
Description: Powershell script file for checking the connectivity to AWS gateway endpoint
Author: Siva Kasina

Version Date        Ticket      Details
1.0     11/21/2023  CSCI-4017   First version

# =================================================================================================================================#>

Clear-Host
If((Test-NetConnection 169.254.169.254 -port 80 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue).TcpTestSucceeded){
    Write-Host "1  Success"
}
Else{ 
    Write-Host "0  Failed"
} 
