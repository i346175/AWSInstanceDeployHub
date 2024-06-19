function Invoke-InstallCertificate{
    param(
        [string]$Destination = "c:\cfn",
        [string]$CertStore = "Cert:\localMachine\My"
    )
    begin{
        $S3Path = "s3://" + $env:aws_envt + "-dbsql-shared/certexport"

    }
    process{
        # New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        if((Get-Service -DisplayName 'Cluster Service' -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "running"}).Count){ $clusterName = Get-Cluster | Select-Object -ExpandProperty Name }
        else{ $clusterName = $env:COMPUTERNAME }

        $env:https_proxy = ''
        if ( $S3Path -ne '' ) {
            $x = aws s3 cp "$S3Path/$clusterName.pfx" "$Destination\$clusterName.pfx"
        }

        $x = Import-PfxCertificate -FilePath "$Destination\$clusterName.pfx" -CertStoreLocation $CertStore -Password (ConvertTo-SecureString -String $clusterName -Force -AsPlainText)
    }
    end{
    }
}
