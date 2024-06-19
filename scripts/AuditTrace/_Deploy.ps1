Clear-Host

$exProp = "TraceLocation"
$exPropValue = "M:\MSSQL\Traces"


$s3Bucket = $env:aws_envt + "-dbsql-rpl"
Get-Module -All | Out-File C:\cfn\get-module.log


try{
    If($($exPropValue).EndsWith('\')){
        $exPropValue = $exPropValue.Substring(0,$exPropValue.Length - 1) ## Get-Location
    }
    
    # 0. Move scripts to server
    Write-Host "$($env:COMPUTERNAME): Copying script files..." -NoNewline
    $env:https_proxy = ""

    aws s3 cp s3://$s3Bucket/AWSInstanceDeployHub/scripts/AuditTrace/ C:\cfn --recursive --quiet

    Write-Host " COMPLETED" -ForegroundColor Green
    
    # 1. Create Extended Property
    Write-Host "$($env:COMPUTERNAME): Creating extended property..." -NoNewline
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | out-null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | out-null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | out-null

    $srv = (New-Object ("Microsoft.SqlServer.Management.Smo.Server") "LOCALHOST")
    $srv.ConnectionContext.TrustServerCertificate = $true
    if($srv.Databases['master'].ExtendedProperties[$exProp]){
        $srv.Databases['master'].ExtendedProperties[$exProp].Drop();
    }
    $prop = New-Object Microsoft.SqlServer.Management.Smo.ExtendedProperty
    $prop.Parent = $srv.Databases['master']
    $prop.Name = $exProp
    $prop.Value = $exPropValue
    $prop.Create()
    Write-Host " COMPLETED" -ForegroundColor Green
    
    # 2. Create directories
    Write-Host "$($env:COMPUTERNAME): Creating directories..." -NoNewline
    If(!(Test-Path "D:\PowershellScripts")){
        $tmp = New-Item -ItemType "directory" -Path "D:\PowershellScripts"
    }
    If(!(Test-Path $exPropValue)){
        $tmp = New-Item -ItemType "directory" -Path $exPropValue
    }
    If(!(Test-Path "$($exPropValue)\Audit\ToSplunk")){
        $tmp = New-Item -ItemType "directory" -Path "$($exPropValue)\Audit\ToSplunk"
    }
    $clusName =  $srv.ClusterName.ToString().Trim() 
    
    If($srv.BackupDirectory.LastIndexOf("\") + 1 -ne $srv.BackupDirectory.Length){
        $traceDestDir = $srv.BackupDirectory + "\Traces\$($clusName)"
    }
    Else{
        $traceDestDir = $srv.BackupDirectory + "Traces\$($clusName)"
    }
    If(!(Test-Path $traceDestDir)){
        $tmp = New-Item -ItemType "directory" -Path $traceDestDir
    } 
    Write-Host " COMPLETED" -ForegroundColor Green
    
    # 3. Copy files CCAuditTableList.json, Archive-TraceFile.ps1
    Write-Host "$($env:COMPUTERNAME): Copying Archive-TraceFile.ps1 file..." -NoNewline
    Copy-Item C:\cfn\CCAuditTableList.json D:\PowershellScripts\CCAuditTableList.json
    Copy-Item C:\cfn\70_Archive-TraceFile.ps1 D:\PowershellScripts\70_Archive-TraceFile.ps1
    Write-Host " COMPLETED" -ForegroundColor Green
    
    # 4. Create Stored Procedure - ResetTrace
    Write-Host "$($env:COMPUTERNAME): Creating Stored Procedure - ResetTrace..." -NoNewline
    Invoke-Sqlcmd -Database master -InputFile "C:\cfn\50_Create_ResetTrace.sql" -QueryTimeout 30
    Write-Host " COMPLETED" -ForegroundColor Green
    
    # 5. Create SQL Agent Job - Archive Trace Files
    Write-Host "$($env:COMPUTERNAME): Creating SQL Agent Job - Archive Trace Files..." -NoNewline
    Invoke-Sqlcmd -Database msdb -InputFile "C:\cfn\60_Create_RemoteTraceCopy_Job.sql" -QueryTimeout 30
    Invoke-Sqlcmd -Database msdb -Query "EXEC msdb..sp_start_job @job_name = N'Archive Trace Files'"  -QueryTimeout 30
    Write-Host " COMPLETED" -ForegroundColor Green
    
    Write-Host "$($env:COMPUTERNAME): All steps COMPLETED!!!" -ForegroundColor Green
}
catch{
    $_ | Format-List -Force | Out-String
}
finally{
    # 6. Close SQL Connection
    if($srv){
        $srv.ConnectionContext.Disconnect();
    }
}