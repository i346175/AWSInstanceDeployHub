Param(
    $thumbprint,
    $expiryDate,
    $vpc,
    $stack,
    $intRunbookURL = "https://wiki.one.int.sap/wiki/display/CONDBA/Integration+Cert+Rotation+and+Patch+Upgrade+Procedure",
    $us2eu2RunbookURL = "https://wiki.one.int.sap/wiki/pages/viewpage.action?pageId=3287720657",
    $psccRunBookURL = "https://wiki.one.int.sap/wiki/display/CONDBA/PSCC+Cert+Rotation+and+Patch+Upgrade+Procedure"
)

if ($env:USERDOMAIN -eq 'integration') {
    $url = $intRunbookURL
} elseif ($env:USERDOMAIN -eq 'uspscc') {
    $url = $psccRunBookURL
} else {
    $url = $us2eu2RunbookURL
}

$snsTopic = "IOPS-DB-PagerDuty"
$accountDetails = Get-EC2InstanceMetadata -Category IdentityDocument | ConvertFrom-Json | Select accountId, region
$awsPartition = (Get-EC2InstanceMetadata -Category Region).PartitionName
$snsArn = "arn:$($awsPartition):sns:$($accountDetails.region):$($accountDetails.accountID):$($snsTopic)"
Publish-SNSMessage -TopicArn $snsArn -Subject "dbsql_CRITICAL_$(($env:AWS_ENVT).ToUpper())_$($vpc)_$([System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName)_MSSQL Cert Expired" -Message "SQL Server Cert has expired on: `r`n
HostName: $([System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName)
StackName: $($stack)
VPC: $($vpc)
Cert Thumbprint: $($thumbprint)
Cert Expiry Date: $($expiryDate) `r`n
Please check the URL below to regenerate the cert: `r`n` $($url)" | Out-Null

