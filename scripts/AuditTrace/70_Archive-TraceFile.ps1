Clear-Host

# ===========================================================================================
# Description: Script to archive trace files to archival location for further archival to S3
# Author: Siva Kasina
# Version History
#   Version Date        Details
#   v1.0    8/25/2020   v1.0 Original version
#   v1.1    10/10/2020  Added code for parsing trace files to generate .xml files for Splunk 
#                           ingestion to meet PCI audit requirement.
#   v2.0    01/20/2021  Removed WHERE filter to audit all tables
#   v2.1    09/09/2021  Code fix to handle standalone
#   v2.2    10/25/2021  BugFix to handle empty trace file
# ===========================================================================================

$localRetentionDays = 7

# 1. GET BACKUP and TRACE LOCATIONS
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | out-null
$srv = (New-Object ("Microsoft.SqlServer.Management.Smo.Server") "LOCALHOST")
$srv.ConnectionContext.TrustServerCertificate = $true

$traceDir = ($srv.Databases["master"].ExtendedProperties["TraceLocation"]).Value
$clusName = $srv.ClusterName.ToString().Trim()

# Code to handle standalones
If($clusName -eq ''){ $clusName = $srv.ComputerNamePhysicalNetBIOS.ToString().Trim() }

If($srv.BackupDirectory.LastIndexOf("\") + 1 -ne $srv.BackupDirectory.Length){
    $traceDestDir = $srv.BackupDirectory + "\Traces\$($clusName)"
}
Else{
    $traceDestDir = $srv.BackupDirectory + "Traces\$($clusName)"
}

# 2. Create trace local archive directory if it does not exist
If(!(Test-Path $traceDestDir)){
    New-Item -ItemType "directory" -Path $traceDestDir
}  

$srvCn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection "."
$srvCn.Connect();

# 3. PARSE, COMPRESS and MOVE THE TRACE FILES AND DELETE ORIGINAL TRACE FILES
$i = Get-ChildItem -Path $traceDir | Where-Object{$_.Name -like "*.trc"} | Sort-Object Name
0..($i.Count - 2)| ForEach-Object{
    try{
        $trcfile = $i[$_].Name
        Write-Host "$($i[$_].FullName)"

        # Parse trace file for Splunk ingestion
        <#
        $inputJSON = Get-Content -Path "D:\PowershellScripts\CCAuditTableList.json" -Raw | ConvertFrom-Json
        $whereClause = ""
        $inputJSON.Environment.TableList | ForEach-Object{
            $whereClause += "TextData LIKE '%$($_.ToString().Trim())%' OR "
        }
        $whereClause = $whereClause.Substring(0,$whereClause.Length - 4)
        #>
        $sql = "SELECT (SELECT StartTime,ServerName,DatabaseName,LoginName,ApplicationName,HostName AS ClientMachine,ObjectName,TextData
            FROM fn_trace_gettable('$($i[$_].FullName)',1) 
            -- WHERE $($whereClause)
            WHERE TextData is NOT NULL
            AND CAST(TextData as VARCHAR(MAX)) NOT LIKE 'select @@spid;%'
            AND CAST(TextData as VARCHAR(MAX)) != 'SET QUOTED_IDENTIFIER OFF'
            AND CAST(TextData as VARCHAR(MAX)) NOT LIKE 'SET TEXTSIZE%'
            AND CAST(TextData as VARCHAR(MAX)) != 'SELECT SYSTEM_USER'
            AND CAST(TextData as VARCHAR(MAX)) != 'SELECT SERVERPROPERTY(''EngineEdition'') AS DatabaseEngineEdition'
            AND CAST(TextData as VARCHAR(MAX)) NOT LIKE 'DECLARE @edition sysname;%'
            AND CAST(TextData as VARCHAR(MAX)) NOT LIKE 'SET ROWCOUNT 0%'
            FOR XML PATH) as XMLData" 
        $r = $srvCn.ExecuteWithResults($sql)
        If($($r.tables.XMLData).Length -gt 0){
            Set-Content -Value $($r.tables.XMLData) -Path "$($traceDir)\Audit\ToSplunk\$($trcfile.Replace('.trc','.xml'))"
        }

        # Create LastParsedFile.txt to track the last parsed file.
        Set-Content -Value "$($trcfile)" -Path "$traceDir\Audit\LastParsedFile.txt"
            
        Compress-Archive -Path $i[$_].FullName -DestinationPath "$($traceDestDir)\$trcfile.zip" -Update
        Remove-Item $i[$_].FullName
    }
    catch{
        throw $_ #| Format-List -Force
    }
    finally{
        $srvCn.Disconnect();
        if($srv){
            $srv.ConnectionContext.Disconnect();
        }
    }
}

# 4. Delete .XML parse files older than $localRetentionDays Hours
Get-ChildItem -Path "$($traceDir)\Audit\ToSplunk\*.xml" `
    | Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-$localRetentionDays)} | Remove-Item

# 5. DELETE COMPRESSED TRACE FILES OLDER THAN 30 DAYS
Get-ChildItem -Path $traceDestDir | Where-Object{($_.Name -like "*.zip") -and ($_.CreationTime -lt $(Get-Date).AddDays(-$($localRetentionDays)))} | ForEach-Object{
    Remove-Item $_.FullName
}

