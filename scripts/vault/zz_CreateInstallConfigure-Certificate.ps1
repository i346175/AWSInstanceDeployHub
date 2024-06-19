Clear-Host
function Get-VaultToken{   
    [cmdletbinding()]
    param(
        #[Parameter(Mandatory)]
        [PSCredential]$Credential,
        #[string]$location = 'v1/auth/aws/login',
        [string]$vault_namespace = 'report/dbsql',
        [string]$aws_region = 'us-west-2',
        [string]$vault_addr = 'https://vault.service.cnqr.tech',
        [string]$AWSRole = 'dbsql'
    )
    begin{
        
    }
    process{

        try{

            $env:https_proxy = ''
            $env:VAULT_NAMESPACE = $vault_namespace
            $env:AWS_REGION = $aws_region
            $env:VAULT_ADDR = $vault_addr
            $awsRole = $AWSRole  
            <#
            $env:VAULT_NAMESPACE = $config.vaultnamespace
            $env:AWS_REGION = $config.awsregion
            $env:VAULT_ADDR = $config.vaultaddress
            $awsRole = $config.vaultnamespace.Split('/')[1]  
            #>
            #if a credential is passed in..assume colo...
            if($null -ne $Credential){
                $uri = "$env:VAULT_ADDR/v1/auth/ldap/login/$($Credential.GetNetworkCredential().UserName)"
                $payload = @{
                    password = $Credential.GetNetworkCredential().Password
                }
                #[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
                [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
                [System.Net.ServicePointManager]::Expect100Continue = $false
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                $data = Set-RestAPIData -APIURL $uri -JSON ($payload | ConvertTo-Json) 
                return $data.auth.client_token;
            }

            if(!(Test-Path -Path 'c:\Vault\Vault.exe' -PathType Leaf)){
                throw "Could not find vault on this computer.  Please ensure the vault.exe is installed at c:\Vault."
            }

            Push-Location
            set-location c:\Vault 

            #$results = $(. ./vault login -method=aws role=$AWSRole )
            $results = $(. ./vault login -method=aws role=$awsRole region=$($env:AWS_REGION))
            $token = ($results | Select-String -Pattern '^token' -List)[0].ToString().Replace('token','').Trim() 


            Pop-Location

            return $token 

        }
        catch{
            #$_ | Format-List -Force
            throw $_ 
        }
        finally{
            #[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        }

    }
    end{

    }
}
function Get-Certificate{
    param(
        [Parameter(Mandatory)]
        [string]$CSR,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [string]$CommonName,
        [string]$URL,
        [int]$TTL = 720,  # 30 days    # 2160 is 90 days
        [string]$vault_namespace = 'report/dbsql',
        [string]$aws_region = 'us-west-2',
        [string]$vault_addr = 'https://vault.service.cnqr.tech',
        [string]$AWSRole = 'dbsql'
    )
    begin{
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Security")
    }
    process{

        #$uri = [uri]::EscapeUriString($URL);
        #below should resolve to "https://vault.service.consul/v1/tools/dbsql/pki/server/sign/dbsql"  
        
        $env:VAULT_NAMESPACE = $vault_namespace
        $env:AWS_REGION = $aws_region
        $env:VAULT_ADDR = $vault_addr
        $awsRole = $AWSRole

        $uri = [uri]::EscapeUriString("$env:VAULT_ADDR/v1/$env:VAULT_NAMESPACE/pki/server/sign/$awsRole");

        #if URL passed in, override the config...
        if($URL){
            $uri = [uri]::EscapeUriString($URL);
        }
        
        $payload = @{
            csr = ([string]$CSR)
            common_name = $CommonName.ToLower()
            ##??  BLewis alt_names = ($AltNames -join ',' )
            ttl = "$($TTL)h"
            use_csr_common_name = $false
            ##?? BLewis use_csr_sans = $false
        }

        $jsonSer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $apiCallBody = $jsonSer.Serialize($payload)
        $apiCallBody = $apiCallBody.Replace("\r\n", "\n")  ## ??BLewis has seen problems with \r\n

        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
        [System.Net.ServicePointManager]::Expect100Continue = $false
        [System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        try{
            $buffer = [System.Text.Encoding]::UTF8.GetBytes( $apiCallBody )
            $req = [System.Net.WebRequest]::Create( $uri )
            $req.headers.Add("X-Vault-Token", $Token )
            $req.Method = "POST"
            $req.Proxy = $null
            $req.ContentType = "application/json"
            $req.ContentLength = $buffer.Length
            $reqStream = $req.GetRequestStream()
            $reqStream.Write($buffer, 0, $buffer.Length)
            $reqStream.Flush()
            $reqStream.Close()
            $resp = $req.GetResponse()
            $reader = new-object System.IO.StreamReader($resp.GetResponseStream())
            $jsonstring = $reader.ReadToEnd()
            $resp = $jsonSer.DeserializeObject($jsonString)
            
            return $resp
        }
        catch [System.Net.WebException] {
            $Request = $_.Exception
            Write-host "Exception caught: $Request"
            if ($_.Exception.Response.StatusCode.value__) {
                $RespStatusCode = ($_.Exception.Response.StatusCode.value__ ).ToString().Trim();
                Write-Host $RespStatusCode;
            }
            if ($_.Exception.Message) {
                $RespMessage = ($_.Exception.Message).ToString().Trim();
                Write-Host $RespMessage;
            }
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            Write-Host $reader.ReadToEnd()
            throw $_ 
        }
        catch{
            Write-Error ($_ | format-list -Force | Out-String)
            throw $_ 
        }
    }
    end{

    }
}
function Get-CertificateRequest{
    param(
        [string]$CommonName,
        [string[]]$AltNames
    )
    begin{

    }
    process{


        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Security")


        $X509PrivateKeyExportFlags = @{
            ALLOW_EXPORT_NONE = 0x0 # Export is not allowed. This is the default value.
            ALLOW_EXPORT = 0x1 # The private key can be exported.
            PLAINTEXT_EXPORT_FLAG = 0x2 # The private key can be exported in plaintext form
            ALLOW_ARCHIVING_FLAG = 0x4 # The private key can be exported once for archiving.
            ALLOW_PLAINTEXT_ARCHIVING_FLAG = 0x8 # The private key can be exported once in plaintext form for archiving.
        }

        $machineCN = [string]::Format( "CN={0}", $CommonName )  
        #the SAN must contain the name of all machines participating within the cluster, plus any CNames, plus listeners...
        $SANNames = $AltNames #| Where-Object{$_ -notlike 'vpc*'}

        $SubjectDN = New-Object -ComObject X509Enrollment.CX500DistinguishedName
        $SubjectDN.Encode( $machineCN , 0x0)
        $PrivateKey = New-Object -ComObject X509Enrollment.CX509PrivateKey -Property @{
            ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
            MachineContext = $true
            Length = 2048
            KeySpec = 1
            KeyUsage = [int][Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment
        }
        $PrivateKey.ExportPolicy = $X509PrivateKeyExportFlags.ALLOW_EXPORT  #<-- I could not find an enum to handle this above
        $PrivateKey.Create()

        if(![System.String]::IsNullOrWhiteSpace($SANNames)){
            $SAN = New-Object -ComObject X509Enrollment.CX509ExtensionAlternativeNames
            $IANs = New-Object -ComObject X509Enrollment.CAlternativeNames
            $SANNames | ForEach-Object {
                # instantiate a IAlternativeName object
                $IAN = New-Object -ComObject X509Enrollment.CAlternativeName
                # initialize the object by using current element in the pipeline
                $IAN.InitializeFromString(0x3,$_)
                # add created object to an object collection of IAlternativeNames
                $IANs.Add($IAN)
            }
            # finally, initialize SAN extension from a collection of alternative names:
            $SAN.InitializeEncode($IANs)
        }

        $KeyUsage = New-Object -ComObject X509Enrollment.CX509ExtensionKeyUsage
        $KeyUsage.InitializeEncode([int][Security.Cryptography.X509Certificates.X509KeyUsageFlags]"DigitalSignature,KeyEncipherment")
        $KeyUsage.Critical = $true
        $EKU = New-Object -ComObject X509Enrollment.CX509ExtensionEnhancedKeyUsage
        $OIDs = New-Object -ComObject X509Enrollment.CObjectIDs
        "Server Authentication", "Client Authentication" | ForEach-Object {
            $netOid = New-Object Security.Cryptography.Oid $_
            $OID = New-Object -ComObject X509Enrollment.CObjectID
            $OID.InitializeFromValue($netOid.Value)
            $OIDs.Add($OID)
        }
        $EKU.InitializeEncode($OIDs)
        $PKCS10 = New-Object -ComObject X509Enrollment.CX509CertificateRequestPkcs10
        $PKCS10.InitializeFromPrivateKey(0x2,$PrivateKey,"")
        $PKCS10.Subject = $SubjectDN
        $PKCS10.X509Extensions.Add($EKU)
        $PKCS10.X509Extensions.Add($KeyUsage)
        if(![System.String]::IsNullOrWhiteSpace($SANNames)){  #newman
            $PKCS10.X509Extensions.Add($SAN);  
        }
        $Request = New-Object -ComObject X509Enrollment.CX509Enrollment
        #$Request.CertificateFriendlyName = $machineFQDN
        $Request.CertificateFriendlyName = $CommonName
        $Request.InitializeFromRequest($PKCS10)
        $Base64CSR = $Request.CreateRequest(0x3)

        return $Base64CSR #-replace "`r`n", "`n"
    }
    end{

    }
}
function Set-Certificate{
    param(
        [Parameter(Mandatory)]
        [string]$Issuing_CA,
        [Parameter(Mandatory)]
        [string]$Certificate,
        [Parameter(Mandatory)]
        [string[]]$RootCert,
        [Parameter(Mandatory)]
        [string]$token,
        [string]$ExportPath = "c:\temp",
        [string]$CertStoreLocation = "Cert:\localMachine\My",
        [switch]$RootOnly
    )
    begin{
        $S3Destination = "s3://" + $env:aws_envt + "-dbsql-shared/certexport"
    }
    process{

        function GetBytesFromPEM() {
            param (
                [string]$pemString,
                [string]$pemType
            )
            $header = [string]::Format( "-----BEGIN {0}-----", $pemType )
            $footer = [string]::Format( "-----END {0}-----", $pemType )
            $start = $pemString.IndexOf( $header, [StringComparison]::Ordinal )
            if ( $start -lt 0 ) {
                return $null
            }
            $start += $header.length
            $end = $pemString.IndexOf( $footer, $start, [StringComparison]::Ordinal ) - $start
            if ( $end -lt 0 ) {
                return $null
            }
            return [System.Convert]::FromBase64String( $pemString.substring( $start, $end ) )
        }

        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Security");
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Security.Cryptography");
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Security.Cryptography.X509Certificates");
        

        #if(-not (Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object{$_.Subject -like 'CN=USPSCC-2019 PKI Root*'})){
        if(-not (Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object{$_.Subject -like 'CN=Fabian*'})){
            foreach($root in $RootCert){
                #root cert (should be on the machine...but found that this is inconsistent..)
                [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$rootCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
                $rootBytes = GetBytesFromPEM -pemString $root -pemType 'CERTIFICATE'
                $rootCert.import( [byte[]]$rootBytes )
                $store = new-object system.security.cryptography.X509Certificates.X509Store( [System.Security.Cryptography.X509Certificates.StoreName]::AuthRoot, "LocalMachine" )
                #$store = new-object system.security.cryptography.X509Certificates.X509Store($CertStoreLocation)
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
                $store.AddRange($rootCert)
            }
        }

        if($RootOnly){
            return;
        }

        #cert authority
        $cacert = new-object system.security.cryptography.x509certificates.x509certificate2collection
        $caBytes = GetBytesFromPEM -pemString $Issuing_CA -pemType 'CERTIFICATE'
        $cacert.import( [byte[]]$caBytes )
        $store = new-object system.security.cryptography.X509Certificates.X509Store( [System.Security.Cryptography.X509Certificates.StoreName]::CertificateAuthority, "LocalMachine" )
        #$store = new-object system.security.cryptography.X509Certificates.X509Store($CertStoreLocation)
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
        $store.AddRange($cacert)

        #leaf cert...
        $certBytes = GetBytesFromPEM -pemString $Certificate -pemType 'CERTIFICATE'
        $cert = new-object system.security.cryptography.x509certificates.x509certificate2collection
        $cert.import( [byte[]]$certBytes )
        $certThumbprint = $cert[0].Thumbprint

        $certB64 = [System.Convert]::ToBase64String($certBytes)
        $Response = New-Object -ComObject X509Enrollment.CX509Enrollment
        $Response.Initialize(0x2)
        $Response.InstallResponse(0,$certB64,0x1,"")

        
        if(-not [System.String]::IsNullOrWhiteSpace($ExportPath)){
            $clusterName = Get-Cluster | Select-Object -ExpandProperty Name 
            $pwd = ConvertTo-SecureString -String $clusterName -Force -AsPlainText
            $cert = Get-ChildItem -Path "$CertStoreLocation\$certThumbprint" 
            
            New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null


            
            Export-PfxCertificate -Cert $cert -FilePath "$ExportPath\$clusterName.pfx" -Password $pwd -ChainOption BuildChain | Out-Null

            #[string[]]$CopyTo = @('EC2AMAZ-NFRAVI3', 'EC2AMAZ-VJBFOJ2')


            #Compress-Archive -Path "$ExportPath\$clusterName.pfx" -DestinationPath "$ExportPath\$clusterName.zip" -Force
            $env:https_proxy = ''
            #aws s3 cp --region us-west-2 "$ExportPath\$clusterName.zip" #--no-verify-ssl
            try{
                aws s3 cp --region us-west-2 "$ExportPath\$clusterName.pfx" $S3Destination/$clusterName.pfx #--no-verify-ssl
            }
            catch{
                $_ | fl -Force
            }
            #Remove-Item -Path "$ExportPath\$clusterName.pfx" -Force | Out-Null
        }
        return $certThumbprint

    }
    end{

    }
}
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

$token = Get-VaultToken

#############################################################
#####           PARAMETER BLOCK                         #####
#############################################################
$CommonName = 'cognosdb-03.report.cnqr.tech'
$altnames = "lst-cognosdb-03.report.cnqr.tech
cognosdbsqlmssql03.report.cnqr.tech
ec2amaz-a0rh6e1.report.cnqr.tech
ec2amaz-p1b2805.report.cnqr.tech
ec2amaz-noovgnl.report.cnqr.tech" -split "`r`n"
#############################################################

$csr = Get-CertificateRequest -CommonName $CommonName -AltNames $altnames
$cert = Get-Certificate -CSR $csr -CommonName $CommonName -Token $token

## Create and Install Certificate
Set-Certificate -Issuing_CA $cert.data.issuing_ca -RootCert $cert.data.ca_chain -Certificate $cert.data.certificate -token $token 


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
