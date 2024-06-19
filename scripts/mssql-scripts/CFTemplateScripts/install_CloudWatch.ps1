Clear-Host

$s3Bucket =  $env:aws_envt + "-dbsql-rpl"

#CloudWatch is not supposed to be on CCPS environment
If($env:aws_envt -eq 'uspscc'){
    Write-Host "CloudWatch is not on CCPS" -ForegroundColor Yellow
    Exit
}


Write-Host "CONFIGURING CW AGENT ON $env:COMPUTERNAME..." -ForegroundColor Yellow
# Setup CW Config as a SSM Parameter Store Value
If(!(Get-SSMParameterValue -Name dbsql-CWConfig).Parameters.Count){
    Write-Host "`tCreating SSM Parameter for CWConfig... " -NoNewline
    aws s3 cp s3://$s3Bucket/AWSInstanceDeployHub/scripts/CloudWatch/CWConfig.json C:\cfn\temp\CWConfig.json --no-progress
    Set-Location C:\cfn\temp\
    aws ssm put-parameter --name "dbsql-CWConfig" --type "String" --value file://CWConfig.json --overwrite 
    ## This is to fix an error - Invalid request: tags and overwrite can't be used together 
    aws ssm add-tags-to-resource --resource-type "Parameter" --resource-id "dbsql-CWConfig" --tags Key=RoleType,Value=dbsql
    Write-Host "COMPLETED" -ForegroundColor Green
}


$region = $env:aws_region
$URL = "https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
$Path = 'C:\cfn\temp\amazon-cloudwatch-agent.msi'

Write-Host "`tCWAgent msi downloading... " -NoNewline
# Download CloudWatchAgent Installer from AWS
Invoke-WebRequest -URI $URL -OutFile $Path
Write-Host "COMPLETED" -ForegroundColor Green

Write-Host "`tCWAgent installing... " -NoNewline
# Install CloudWatch Agent 
Start-Process -FilePath "$Path" -Wait -ArgumentList "/quiet" 
Write-Host "COMPLETED" -ForegroundColor Green

Write-Host "`tCWAgent Service starting... " -NoNewline
# START CW AGENT USING CONFIG FROM SSM PARAMETER STORE
& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -s -c ssm:dbsql-CWConfig
Write-Host "STARTED... " -ForegroundColor Green