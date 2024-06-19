param(
    [parameter(Mandatory=$true)][int]$NVMe
)

$mssqlScriptsFolder="C:\mssql-scripts" 
Set-Location $mssqlScriptsFolder 
$logsFolder = "$mssqlScriptsFolder\automation_logs"
if(!(Test-Path -Path $logsFolder)){ 
    New-Item -ItemType "directory" -Path $logsFolder | Out-Null 
}
$timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
$logFile = "$logsFolder\invoke_storage_config_log_$timestamp.log"

try {
    Write-Output (">>>>>>>>>> STARTED | invoke_storage_config | $(Get-Date -format 'u') >>>>>>>>>>") | Out-File -FilePath $logFile
    if($NVMe){$cnt = 4}
    else{$cnt = 5}
    
    #Configuring drive letters for EBS volumes
    for($i = 1; $i -le $cnt; $i += 1) {
        $diskNumber = $i
        Initialize-Disk -Number $diskNumber
        Write-Output "Mapping EBS device disk number: [$diskNumber]" | Out-File -Append $logFile
        $ebsVol = C:\ProgramData\Amazon\Tools\ebsnvme-id.exe $diskNumber
        Write-Output "Configuring EBS Volume: [$ebsVol]" | Out-File -Append $logFile
        $deviceName = $ebsVol[2]
        switch -wildcard ($deviceName){
            "*xvdd*" {$driveLetter = 'D';$driveLabel = 'OPSDrive'; break}
            "*xvde*" {$driveLetter = 'E';$driveLabel = 'DBDataDrive'; break}
            "*xvdf*" {$driveLetter = 'F';$driveLabel = 'TempDBDrive'; break}
            "*xvdg*" {$driveLetter = 'G';$driveLabel = 'DBTranLogDrive'; break}
            "*xvdm*" {$driveLetter = 'M';$driveLabel = 'Backup'; break}
        }
        Write-Output "Setting drive letter $driveLetter and drive label [$driveLabel] for [$deviceName]" | Out-File -Append $logFile
        New-Partition -DiskNumber $diskNumber -DriveLetter "$driveLetter" -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel "$driveLabel"
    }
    
    $instance = wget http://169.254.169.254/latest/dynamic/instance-identity/document -UseBasicParsing | ConvertFrom-Json 
    $inst_id = $instance.instanceId 
    $tags = (aws ec2 describe-tags --filters "Name=resource-id,Values=$inst_id" | ConvertFrom-Json).Tags | Where-Object {$_.Key -in ("Name", "HostName", "MicroService")} | Select-Object Key, Value 
    $key1 = $($tags[0].Key.ToString()) 
    $value1 = $($tags[0].Value.ToString()) 
    $key2 = $($tags[1].Key.ToString()) 
    $value2 = $($tags[1].Value.ToString()) 
    $key3 = $($tags[2].Key.ToString()) 
    $value3 = $($tags[2].Value.ToString()) 
    $volume_ids = $(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=$inst_id | ConvertFrom-Json).Volumes.Attachments.VolumeId 
    
    #Adding Tags on EBS volumes
    Write-Output "Adding Tags on EBS volumes - STARTED" | Out-File -Append $logFile
    $volume_ids | ForEach-Object{  
        aws ec2 create-tags --resources $($_) --tags Key="$key1",Value="$value1" Key="$key2",Value="$value2" Key="$key3",Value="$value3"  
    }
    Write-Output "Adding Tags on EBS volumes - COMPLETED" | Out-File -Append $logFile

    if($NVMe){
        #Configuring drive letter F-drive for local NVMe
        Write-Output "Configuring drive letter F-drive for local NVMe - STARTED" | Out-File -Append $logFile
        $driveLetter = 'F'
        $partitionStyle = 'GPT'
        $volLabel = 'TempDBDrive'
        Get-Disk | Where-Object {$_.PartitionStyle -eq "RAW"} | Select-Object -First 1 `
            | Initialize-Disk -PartitionStyle $partitionStyle -PassThru `
            | New-Partition -DriveLetter $driveLetter -UseMaximumSize `
            | Format-Volume -FileSystem NTFS -NewFileSystemLabel $volLabel | Format-Table -AutoSize
        Write-Output "Configuring drive letter F-drive for local NVMe - COMPLETED" | Out-File -Append $logFile
        
        #Configuring scheduler task to map NVMe drive
        Write-Output "Configuring scheduler task to map NVMe volume as F-drive - STARTED" | Out-File -Append $logFile
        $scriptPath = "D:\PowershellScripts"
        if(!(Test-Path -Path $scriptPath)){ 
            New-Item -ItemType "directory" -Path $scriptPath | Out-Null 
        }
        Copy-Item -Path "$mssqlScriptsFolder\CFTemplateScripts\Set-NVMeVolume.ps1" -Destination "$scriptPath\Set-NVMeVolume.ps1"
        $TaskName = 'SetNVMEVolume'
        $TaskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $TaskName }
        if($TaskExists){ 
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$False
        }
        Register-ScheduledTask -TaskName $TaskName -Xml $(Get-Content -Path "$mssqlScriptsFolder\CFTemplateScripts\SetNVMeVolume.xml" | Out-String)
        Write-Output "Configuring scheduler task to map NVMe volume as F-drive - COMPLETED" | Out-File -Append $logFile    
    }
    
    Write-Output ("<<<<<<<<<< COMPLETED | invoke_storage_config | $(Get-Date -format 'u') <<<<<<<<<<") | Out-File -Append $logFile
} catch { 
    $_ | Format-List -Force | Out-File -Append $logFile
    Write-Output ("<<<<<<<<<< FAILED | invoke_storage_config | $(Get-Date -format 'u') <<<<<<<<<<") | Out-File -Append $logFile
}
