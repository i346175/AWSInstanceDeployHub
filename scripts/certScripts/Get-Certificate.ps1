function Get-Certificate{
    param(
        [Parameter(Mandatory)]
        [string]$CSR,
        [Parameter(Mandatory)]
        [string]$Token,
        [Parameter(Mandatory)]
        [string]$CommonName,
        [string]$URL,
        [int]$TTL = 90,  # 30 days    # 2160 is 90 days
        [string]$vault_namespace = 'tools/dbsql',
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