function Run-ConfigureCertificate{
    begin{
        $CollectionParam = (Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server" | Where-Object{$_.Name -like '*.MSSQLSERVER*'}).Name.split('\')[-1]
    }
    process{
        #############################################################
        ## Configure Certificate for SQL Server and Set Permissions #
        #############################################################
        if((Get-Service -DisplayName 'Cluster Service' -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "running"}).Count){ $clusterName = Get-Cluster | Select-Object -ExpandProperty Name }
        else{ $clusterName = $env:COMPUTERNAME }
            # $clusterName 

        if([System.String]::IsNullOrEmpty($clusterName)){
            throw "no cluster name found on computer $env:COMPUTERNAME"
        }
        Push-Location
        Set-Location Cert:\LocalMachine\My
        $thumb = Get-ChildItem | Where-Object{$_.Subject -like "CN=$clusterName*"} | Sort-Object NotBefore -Descending | Select-Object -First 1 -ExpandProperty Thumbprint
        Pop-Location

        ## Set Certificate thumprint for SQLServer
        if([System.String]::IsNullOrEmpty($thumb)){
            throw "no thumbrpint found on computer $env:COMPUTERNAME"
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$CollectionParam\MSSQLServer\SuperSocketNetLib" -Name Certificate -Value $thumb

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
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$CollectionParam\MSSQLServer\SuperSocketNetLib" -Name ForceEncryption -Value 1
    }
    end{
    }
}