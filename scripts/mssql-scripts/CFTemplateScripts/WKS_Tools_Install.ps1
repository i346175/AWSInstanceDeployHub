param(
    [parameter(Mandatory=$true)][string]$roleType,
    [parameter(Mandatory=$true)][string]$StackName,
    [parameter(Mandatory=$true)][string]$Region,
    [parameter(Mandatory=$true)][string]$Environment,
    [parameter(Mandatory=$true)][string]$Proxy 
)


try{
    Set-TimeZone -Id 'Pacific Standard Time'
    
    If($roleType -eq 'dbsql'){return;}

    Write-Output '>>>>>ADDing dbsql_admins group to local Administrator group<<<<<'
    Add-LocalGroupMember -Group 'Administrators' -Member "dbsql_admins" 
    
    #make from $Environment small letter
    $envt = $Environment.ToLower()
    
    $s3Bucket = $envt + "-dbsql-rpl"
    $s3BucketPath = "$s3Bucket/AWSInstanceDeployHub/scripts"

    Write-Output '>>>>>STARTED: Copying powershell module<<<<<'
    aws s3 cp s3://$s3BucketPath/DPA/DPA.zip C:\cfn\DPA.zip --no-progress
    Expand-Archive C:\cfn\DPA.zip "C:\Program Files\WindowsPowerShell\Modules\"
    Remove-Item C:\cfn\DPA.zip

    aws s3 cp s3://$s3BucketPath/Tools.zip C:\cfn\Tools.zip --no-progress
    Expand-Archive C:\cfn\Tools.zip D:\
    Copy-Item D:\Tools\Powershell\Modules\ "C:\Program Files\WindowsPowerShell\" -Force -Recurse
    Remove-Item C:\cfn\Tools.zip

    aws s3 cp s3://$s3BucketPath/Concur.SqlBuild.zip C:\cfn\Concur.SqlBuild.zip --quiet
    Expand-Archive -Path C:\cfn\Concur.SqlBuild.zip -DestinationPath "C:\Program Files\WindowsPowerShell\Modules" -Force
    Remove-Item C:\cfn\Concur.SqlBuild.zip
    Write-Output '>>>>>COMPLETED: Copying powershell module<<<<<'

    Write-Output '>>>>>STARTED: Installing Failover Cluster Mgmt Tools<<<<<'
    Install-WindowsFeature -Name RSAT-Clustering-Mgmt, RSAT-Clustering-PowerShell, RSAT-AD-PowerShell, RSAT-ADDS-Tools, RSAT-DNS-Server, Telnet-Client | Out-Null
    Write-Output '>>>>>COMPLETED: Installing Failover Cluster Mgmt Tools<<<<<'

    Write-Output '>>>>>STARTED: Installing SQL Mgmt Studio<<<<<'
    aws s3 cp s3://$s3BucketPath/SSMS-Setup-ENU.exe C:\cfn\SSMS-Setup-ENU.exe --quiet
    New-Item -Path C:\cfn\SSMSInstallLogs -ItemType Directory | Out-Null
    Start-Process C:\cfn\SSMS-Setup-ENU.exe -Wait -ArgumentList '/install /quiet /norestart /log C:\cfn\SSMSInstallLogs\ssmsInstall.log'
    Remove-Item C:\cfn\SSMS-Setup-ENU.exe
    Write-Output '>>>>>COMPLETED: Installing SQL Mgmt Studio<<<<<'

    Write-Output '>>>>>STARTED: Update /profile.ps1 file<<<<<'
    #Set-Content -Value "Import-Module SqlServer, DNSServer, ActiveDirectory, FailoverClusters -DisableNameChecking -Force" -Path "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1" 
    Set-Content -Value "Import-Module SqlServer, FailoverClusters -DisableNameChecking -Force" -Path "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1" 
    Add-Content -Value "netsh winhttp reset proxy" -Path "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1" 
    Write-Output '>>>>>COMPLETED: Update /profile.ps1 file<<<<<'
    Write-Output '>>>>>SENDING Script Completion Signal<<<<<'
    if ($Environment -in ('INTEGRATION','USPSCC')) {
        cfn-signal.exe -e 0 --region $Region --resource 'ToolsInstallWaitCondition' --stack $StackName --https-proxy $Proxy
    } else {
        $env:https_proxy=''
        cfn-signal.exe -e 0 --region $Region --resource 'ToolsInstallWaitCondition' --stack $StackName
    }
    Write-Output 'Restarting computer...'
    Restart-Computer -Force
}
catch{
    $_
}