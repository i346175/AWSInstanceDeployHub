$driveLetter = 'D' 
$driveLabel = 'OPSDrive' 
Initialize-Disk -Number 1 
New-Partition -DiskNumber 1 -DriveLetter "$driveLetter" -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel "$driveLabel" 
Write-Output "Storage Config task completed" 