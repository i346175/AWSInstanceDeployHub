# ================================================================================================================================
# DESCRIPTION:  Script to configure system page file 
# AUTHOR:       Siva Kasina

# VERSION HISTORY
# DATE      TICKET      VERSION CHANGE_DESCRIPTION
# 12/1/2023 CSCI-6476   1.0     Script creation
# ================================================================================================================================
param(
    [parameter(Mandatory=$true)][string]$pageFileSizeMB
)

try{
    #DISABLE AUTOMATIC MANAGED PAGE FILE FOR ALL DRIVES EXCEPT C-DRIVE
    $pagefile = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
    $pagefile.AutomaticManagedPagefile = $false 
    $pagefile.put() | Out-Null 

    # SETTING NON-SYSTEM-MANAGED PAGE FILE ON D-DRIVE 
    Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{name="D:\pagefile.sys"; InitialSize = $pageFileSizeMB; MaximumSize = $pageFileSizeMB} -EnableAllPrivileges | Out-Null   

    # DELETING PAGE FILE ON C-DRIVE 
    $pagefileset = Get-WmiObject Win32_pagefilesetting | Where-Object { $_.Name -like "C*" }
    $pagefileset.Delete()

    Write-Host "Page file Configuration - COMPLETED SUCCESSFULLY" 
}
catch{
    $_ | Format-List -Force
}

