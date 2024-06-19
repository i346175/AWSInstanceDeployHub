$timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
Write-Output (">>>>>>>>>> Started configure_Amazon_SSMAgent at: $(Get-Date -format 'u') >>>>>>>>>>")
$PROXY="http://proxy.service.cnqr.tech:3128"
$PROXYBYPASS="169.254.169.254;ssm.us-west-2.amazonaws.com;ssmmessages.us-west-2.amazonaws.com;ssm.eu-central-1.amazonaws.com;ssmmessages.eu-central-1.amazonaws.com;ec2messages.us-west-2.amazonaws.com;localhost;127.0.0.1;169.254.169.123;169.254.169.254;dynamodb.us-west-2.amazonaws.com;ec2.us-west-2.amazonaws.com;kms.us-west-2.amazonaws.com;logs.us-west-2.amazonaws.com;logs.eu-central-1.amazonaws.com;s3.eu-central-1.amazonaws.com;*.s3.eu-central-1.amazonaws.com;s3.us-west-2.amazonaws.com;s3.dualstack.us-west-2.amazonaws.com;secretsmanager.us-west-2.amazonaws.com;sns.us-west-2.amazonaws.com;sqs.us-west-2.amazonaws.com;sts.us-west-2.amazonaws.com;*.cnqr.io;*.cnqr.delivery;*.cnqr.tech;*.consul;*.elb.amazonaws.com;iam.amazonaws.com"
netsh winhttp set proxy proxy-server="$PROXY" bypass-list="$PROXYBYPASS"
$serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\AmazonSSMAgent"
$keyInfo = (Get-Item -Path $serviceKey).GetValue("Environment")
$proxyVariables = @("http_proxy=http://proxy.service.cnqr.tech:3128", "no_proxy=169.254.169.254,ssm.us-west-2.amazonaws.com,ssmmessages.us-west-2.amazonaws.com,ssm.eu-central-1.amazonaws.com,ssmmessages.eu-central-1.amazonaws.com,ec2messages.us-west-2.amazonaws.com,localhost,127.0.0.1,169.254.169.123,169.254.169.254,dynamodb.us-west-2.amazonaws.com,ec2.us-west-2.amazonaws.com,kms.us-west-2.amazonaws.com,logs.us-west-2.amazonaws.com,logs.eu-central-1.amazonaws.com,s3.eu-central-1.amazonaws.com,*.s3.eu-central-1.amazonaws.com,s3.us-west-2.amazonaws.com,s3.dualstack.us-west-2.amazonaws.com,secretsmanager.us-west-2.amazonaws.com,sns.us-west-2.amazonaws.com,sqs.us-west-2.amazonaws.com,sts.us-west-2.amazonaws.com,*.cnqr.io,*.cnqr.delivery,*.cnqr.tech,*.consul,*.elb.amazonaws.com,iam.amazonaws.com")
If($keyInfo -eq $null){
    New-ItemProperty -Path $serviceKey -Name Environment -Value $proxyVariables -PropertyType MultiString -Force
}
else{
    Set-ItemProperty -Path $serviceKey -Name Environment -Value $proxyVariables
}
$ExecResults = Get-ItemProperty -Path $serviceKey
Write-Output $ExecResults
Restart-Service AmazonSSMAgent | Out-Null 
Write-Output ("<<<<<<<<<< Completed configure_Amazon_SSMAgent at: $(Get-Date -format 'u') <<<<<<<<<<")
