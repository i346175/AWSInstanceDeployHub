function Get-VaultToken{   
    [cmdletbinding()]
    param(
        #[Parameter(Mandatory)]
        [PSCredential]$Credential,
        #[string]$location = 'v1/auth/aws/login',
        [string]$vault_namespace = 'tools/dbsql',
        [string]$aws_region = 'us-west-2',
        [string]$vault_addr = 'https://vault.service.cnqr.tech',
        [string]$AWSRole = 'dbsql'
    )
    begin{
        
    }
    process{

        try{

            
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

