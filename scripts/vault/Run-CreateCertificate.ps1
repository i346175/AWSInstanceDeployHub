function Run-CreateCertificate{   
    param(
        [string]$CommonName,
        [string[]]$AltNames,
        [string]$vault_namespace = 'tools/dbsql',
        [string]$aws_region = 'us-west-2',
        [int]$TTL = 90
    )
    begin{
        $S3Destination = "s3://" + $env:aws_envt + "-dbsql-shared/certexport"
    }
    process{
        . C:\Vault\Get-VaultToken.ps1
        . C:\Vault\Get-CertificateRequest.ps1
        . C:\Vault\Get-Certificate.ps1
        . C:\Vault\Set-Certificate.ps1

        $token = Get-VaultToken -vault_namespace $vault_namespace -aws_region $aws_region
        $csr = Get-CertificateRequest -CommonName $CommonName -AltNames $Altnames
        $cert = Get-Certificate -CSR $csr -CommonName $CommonName -Token $token -TTL $TTL -vault_namespace $vault_namespace -aws_region $aws_region

        ## Create and Install Certificate
        Set-Certificate -Issuing_CA $cert.data.issuing_ca -RootCert $cert.data.ca_chain -Certificate $cert.data.certificate -token $token -aws_region $aws_region
    }
    end{
    }
}





