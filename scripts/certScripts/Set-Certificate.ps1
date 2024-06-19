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
        [string]$ExportPath = "c:\cfn",
        [string]$CertStoreLocation = "Cert:\localMachine\My",
        [string]$aws_region = 'us-west-2',
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
        # if(-not (Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object{$_.Subject -like 'CN=Fabian*'})){
            foreach($root in $RootCert){
                #root cert (should be on the machine...but found that this is inconsistent..)
                [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]$rootCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
                $rootBytes = GetBytesFromPEM -pemString $root -pemType 'CERTIFICATE'
                $rootCert.import( [byte[]]$rootBytes )
                #$store = new-object system.security.cryptography.X509Certificates.X509Store( [System.Security.Cryptography.X509Certificates.StoreName]::AuthRoot, "LocalMachine" )
                ##$store = new-object system.security.cryptography.X509Certificates.X509Store($CertStoreLocation)
                #$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
                #$store.AddRange($rootCert)

                if($rootCert.Issuer -eq $rootCert.Subject){
                    $store = new-object system.security.cryptography.X509Certificates.X509Store( [System.Security.Cryptography.X509Certificates.StoreName]::AuthRoot, "LocalMachine" )
                    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
                    $store.AddRange($rootCert)
                }
                else{  #ca cert...
                    $store = new-object system.security.cryptography.X509Certificates.X509Store( [System.Security.Cryptography.X509Certificates.StoreName]::CertificateAuthority, "LocalMachine" )
                    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadWrite")
                    $store.AddRange($rootCert)
                }
            }
        # }

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
            if((Get-Service -DisplayName 'Cluster Service' -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "running"}).Count){ $clusterName = Get-Cluster | Select-Object -ExpandProperty Name }
            else{ return $certThumbprint } 
             
            $pswd = ConvertTo-SecureString -String $clusterName -Force -AsPlainText
            $cert = Get-ChildItem -Path "$CertStoreLocation\$certThumbprint" 
            
            New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null


            
            Export-PfxCertificate -Cert $cert -FilePath "$ExportPath\$clusterName.pfx" -Password $pswd -ChainOption BuildChain | Out-Null

            #[string[]]$CopyTo = @('EC2AMAZ-NFRAVI3', 'EC2AMAZ-VJBFOJ2')


            #Compress-Archive -Path "$ExportPath\$clusterName.pfx" -DestinationPath "$ExportPath\$clusterName.zip" -Force
            $env:https_proxy = ''
            #aws s3 cp --region us-west-2 "$ExportPath\$clusterName.zip" #--no-verify-ssl
            if ( $S3Destination -ne '' ) {
                try{
                    aws s3 cp --region $aws_region "$ExportPath\$clusterName.pfx" $S3Destination/$clusterName.pfx | Out-Null
                }
                catch{
                    $_ | fl -Force
                }
            }
            #Remove-Item -Path "$ExportPath\$clusterName.pfx" -Force | Out-Null
        }
        return $certThumbprint

    }
    end{

    }
}
