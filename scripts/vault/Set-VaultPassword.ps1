function Set-VaultPassword{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [PSCredential]$Account,
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

        $Name = $Account.GetNetworkCredential().UserName
                
        $env:VAULT_NAMESPACE = $vault_namespace
        $env:AWS_REGION = $aws_region
        $env:VAULT_ADDR = $vault_addr
        $awsRole = $AWSRole

        $headers = @{}
        $headers.Add("X-Vault-Token", $token)
        $headers.Add("ContentType", "application/json")

        #[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
        [System.Net.ServicePointManager]::Expect100Continue = $false
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

        $location = "v1/$env:vault_namespace/secret/$Name"

        $uri = [uri]::EscapeUriString("$env:vault_addr/$location");

        $payload = @{
            password = $Account.GetNetworkCredential().Password
            createdby = $env:USERNAME
            createdate = (get-date).ToString('yyyyMMdd HH:mm:ss')
            computername = $env:COMPUTERNAME
        }
        $json = $payload | ConvertTo-Json 

        $result = Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $json -Headers $headers #-Proxy $config.proxy
        $result

    }
    end{

    }
}
