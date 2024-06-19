<#
PROCEDURE / STEPS
    1. Identify Offline volume
    2. Initialize the drive and create GPT volume
    3. Create directory structures
    4. Start SQL Services if not running
#>

$driveLetter = @('F')
$partitionStyle = 'GPT'
$logPath = "D:\Logs\Set-NVMeVolume.log"

"$(Get-Date): Task STARTED ..." | Out-File -FilePath $logPath 
$i = 0
if(!(Test-Path -Path "$($driveLetter[$i]):\")){
    try{
        Get-Disk | Where-Object {$_.PartitionStyle -eq "RAW"} | Select-Object -First 1 | ForEach-Object{
            $disk = $_
            switch ($($driveLetter[$i])){
                'F' { $fullPath = "F:\MSSQL\Data"; $volLabel = 'TempDBDrive'; Break }
                'G' { $fullPath = "G:\MSSQL\TranLog"; $volLabel = 'DBTranLogDrive'; Break }
                Default { $fullPath = "$($driveLetter[$i]):\MSSQL\Data"; $volLabel = 'DBDataDrive'; Break }
            }
    
            # IDENTIFY OFFLINE VOLUME, INITIALIZE THE DRIVE AND CREATE GPT VOLUME PARITION AND ASSIGN DRIVE LETTER
            "`t$(Get-Date): Creating volume partition $($driveLetter[$i]) ..." | Out-File -FilePath $logPath -Append
            $disk | Initialize-Disk -PartitionStyle $partitionStyle -PassThru `
                | New-Partition -DriveLetter $driveLetter[$i] -UseMaximumSize `
                | Format-Volume -FileSystem NTFS -NewFileSystemLabel $volLabel | Format-Table -AutoSize
    
            # CREATE DIRECTORY STRUCTURES
            "`t$(Get-Date): Creating directory $fullPath ..." | Out-File -FilePath $logPath -Append
            if(!(Test-Path -Path $fullPath)){
                New-Item -Path $fullPath -ItemType Directory | Out-Null
            }
            $i += 1
        }
    
        # START SQL SERVICES IF NOT RUNNING
        if(!(Get-Service -Name MSSQLSERVER | Where-Object {$_.Status -eq "Running"})){
            "`t$(Get-Date): Starting SQL Services ..." | Out-File -FilePath $logPath -Append
            Start-Service -Name MSSQLSERVER
            Start-Service -Name SQLSERVERAGENT
        }
    }
    catch{
        $_ |  Out-File -FilePath $logPath -Append
    }
}
Else{
    "`t$(Get-Date): F-drive already EXISTS! NO ACTION performed..." |  Out-File -FilePath $logPath -Append
}
"$(Get-Date): Task COMPLETED ..." | Out-File -FilePath $logPath -Append
