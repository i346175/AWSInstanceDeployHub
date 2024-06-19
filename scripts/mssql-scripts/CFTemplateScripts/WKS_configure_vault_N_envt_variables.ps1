param(
    [parameter(Mandatory=$true)][string]$Environment,
    [parameter(Mandatory=$true)][string]$Region,
    [parameter(Mandatory=$true)][string]$s3bucket
)
try{
    Write-Output (">>>>>>>>>> Started enable_env_variable at: $(Get-Date -format 'u') >>>>>>>>>>")
    [System.Environment]::SetEnvironmentVariable('aws_envt',$Environment.ToLower(),[System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('aws_region',$Region.ToLower(),[System.EnvironmentVariableTarget]::Machine)
    $no_proxy_DRS = "$($env:no_proxy);drs.$($env:aws_region).amazonaws.com;*.s3.$($env:aws_region).amazonaws.com' " 
    [System.Environment]::SetEnvironmentVariable('no_proxy',$no_proxy_DRS,[System.EnvironmentVariableTarget]::Machine)
    write-output ("<<<<<<<<<< Completed enable_env_variable at: $(Get-Date -format 'u') <<<<<<<<<<")
    $DownloadURL = "s3://$s3bucket/AWSInstanceDeployHub/scripts/vault"
    $vaultPath = "C:\vault"
    Write-Output (">>>>>>>>>> Started configure_vault at: $(Get-Date -format 'u') >>>>>>>>>>")
    $env:https_proxy = ''
    New-Item -ItemType Directory -Path $vaultPath -Force | out-null
    aws s3 cp $DownloadURL $vaultPath --recursive --no-progress --quiet
    Write-Output ("<<<<<<<<<< Completed configure_vault at: $(Get-Date -format 'u') <<<<<<<<<<")
}
catch{
    $_
}

