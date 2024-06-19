function global:Format-LogMessage {
    $msg = $($args[0])
    $kibanaLogsFolder = "C:\logs"
    $Global:kibanaLogsFile = "$kibanaLogsFolder\application.log"

    If ((Test-Path $kibanaLogsFolder) -eq $false) {
        New-Item -ItemType "directory" -Path $kibanaLogsFolder
    }

    $logStatement = @{type="log";application="DBFormation_MSSQL";roletype=$RoleType;description="$msg";level="INFO";data_version=2;stackname=$StackName }
    $logStatement = ($logStatement | ConvertTo-Json -Compress)
    $logStatement.ToString() | Out-File -Append  -Encoding ASCII $kibanaLogsFile
    return $msg
}