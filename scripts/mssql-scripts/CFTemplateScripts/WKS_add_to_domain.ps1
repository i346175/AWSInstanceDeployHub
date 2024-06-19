param(
    [parameter(Mandatory=$true)][string]$S3Bucket,
    [parameter(Mandatory=$true)][string]$DomainSuffice,
    [parameter(Mandatory=$true)][string]$Region,
    [parameter(Mandatory=$true)][string]$StackName 
)
try{
    $ScriptPath = 'C:\cfn\temp' 
    $S3Bucket = "s3://$S3Bucket/AWSInstanceDeployHub/scripts/mssql-scripts"
    aws s3 cp $S3Bucket/domainjoin.ps1 $ScriptPath\domainjoin.ps1 --no-progress
    $script = Get-Content $ScriptPath\domainjoin.ps1 
    $script = $script.Replace('<DomainSuffix>',$DomainSuffice) 
    $script = $script.Replace('<ProvisioningAccount>','sa_dba_prov').Replace('<VaultNamespace>','tools/dbsql') 
    $script = $script.Replace('<awsRegion>',$Region) 
    Set-Content -Path "$ScriptPath\domainjoin.ps1" -Value $script 
    $response = C:\cfn\temp\domainjoin.ps1 
} catch { 
    $ProxyVar = $env:https_proxy
    $env:https_proxy = ''
    cfn-signal.exe -e 1 --region $Region --resource 'Master' --stack $StackName
    $env:https_proxy = $ProxyVar 
} 
Write-Output "Domain Join Response: $response"
