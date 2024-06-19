function Get-VaultPassword{
    
    [cmdletbinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$token,
        [string]$vault_namespace = 'tools/dbsql',
        [string]$aws_region = 'us-west-2',
        [string]$vault_addr = 'https://vault.service.cnqr.tech',
        [string]$AWSRole = 'dbsql'
    )
    begin{

    }
    process{

        $env:VAULT_NAMESPACE = $vault_namespace
        $env:AWS_REGION = $aws_region
        $env:VAULT_ADDR = $vault_addr
        $awsRole = $AWSRole 

        $location = "v1/$env:vault_namespace/secret/$Name"
        $uri = [uri]::EscapeUriString("$env:vault_addr/$location");

        $headers = @{}
        $headers.Add("X-Vault-Token", $token)
        $headers.Add("ContentType", "application/json")
                
        try{
            #[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
            [System.Net.ServicePointManager]::Expect100Continue = $false
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

            $pwd = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers $headers #-Proxy $config.proxy
        }
        catch{
            $_ | fl -Force
        }
        finally{
            
        }
                
        return New-Object System.Management.Automation.PSCredential ($Name, (ConvertTo-SecureString $pwd.data.password -AsPlainText -Force))

    }
    end{

    }
}