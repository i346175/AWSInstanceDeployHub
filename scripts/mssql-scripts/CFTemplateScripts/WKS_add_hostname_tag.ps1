try { 
    $instance = wget http://169.254.169.254/latest/dynamic/instance-identity/document -UseBasicParsing | ConvertFrom-Json 
    $inst_id = $instance.instanceId 
    $key = "HostName" 
    $value = $env:COMPUTERNAME 
    aws ec2 create-tags --resources $inst_id --tags "Key=$key,Value=$value" 
    Write-Output "Added Hostname tag" 
} catch { 
    Write-Output "Failed to add Hostname tag"
    $_
} 
