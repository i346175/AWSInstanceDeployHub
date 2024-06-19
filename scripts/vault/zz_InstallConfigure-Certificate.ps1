Clear-Host
function Invoke-InstallCertificate{
    param(
        [string]$Destination = "c:\temp",
        [string]$CertStore = "Cert:\localMachine\My"
    )
    begin{
        $S3Path = "s3://" + $env:aws_envt + "-dbsql-shared/certexport"
    }
    process{

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        $clusterName = Get-Cluster | Select-Object -ExpandProperty Name 

        $env:https_proxy = ''
        aws s3 cp "$S3Path/$clusterName.pfx" "$Destination\$clusterName.pfx"

        Import-PfxCertificate -FilePath "$Destination\$clusterName.pfx" -CertStoreLocation $CertStore -Password (ConvertTo-SecureString -String $clusterName -Force -AsPlainText)


    }
    end{

    }
}
## Install Certificate from .pfx file
Invoke-InstallCertificate

#############################################################
## Configure Certificate for SQL Server and Set Permissions #
#############################################################
$clusterName = Get-Cluster | Select-Object -Expand Name 
$clusterName 

if([System.String]::IsNullOrEmpty($clusterName)){
    throw "no cluster name found on computer $env:COMPUTERNAME"
}
Push-Location
Set-Location Cert:\LocalMachine\My
$thumb = Get-ChildItem | Where-Object{$_.Subject -like "CN=$clusterName*"} | Select-Object -ExpandProperty Thumbprint 
Pop-Location

## Set Certificate thumprint for SQLServer
if([System.String]::IsNullOrEmpty($thumb)){
    throw "no thumbrpint found on computer $env:COMPUTERNAME"
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib" -Name Certificate -Value $Thumb

## Set Certificate permission to SQL Servive Account
$Service = Get-CIMInstance win32_service  | Where-Object {$_.Name -eq 'MSSQLServer'} 
$userName = $Service.StartName.Split('\')[1]

if([System.String]::IsNullOrEmpty($userName)){
    throw "Could not retrieve sql server service account on computer $env:COMPUTERNAME"
}

$root = "c:\programdata\microsoft\crypto\rsa\machinekeys"
$rule = new-object security.accesscontrol.filesystemaccessrule $userName, Read, allow
Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object{$_.thumbprint -eq $thumb} | ForEach-Object{
    $keyname = $_.privatekey.cspkeycontainerinfo.uniquekeycontainername
    $p = [io.path]::combine($root, $keyname)
    if ([io.file]::exists($p)){
        $acl = get-acl -path $p
        $acl.addaccessrule($rule)
        set-acl $p $acl
    }
}

## Enable Force Encryption for SQL Server
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib" -Name ForceEncryption -Value 1
