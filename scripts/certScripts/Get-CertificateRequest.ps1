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

