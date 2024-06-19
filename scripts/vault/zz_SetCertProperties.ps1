$clusterName = Get-Cluster | Select-Object -Expand Name 
$clusterName 

if([System.String]::IsNullOrEmpty($clusterName)){
    throw "no cluster name found on computer $env:COMPUTERNAME"
}



Push-Location
sl Cert:\LocalMachine\My
$thumb = gci | ?{$_.Subject -like "CN=$clusterName*"} | select -ExpandProperty Thumbprint 
Pop-Location

if([System.String]::IsNullOrEmpty($thumb)){
    throw "no thumbrpint found on computer $env:COMPUTERNAME"
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib" -Name Certificate -Value $Thumb

#set cert permission
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

#set force encryption
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib" -Name ForceEncryption -Value 1