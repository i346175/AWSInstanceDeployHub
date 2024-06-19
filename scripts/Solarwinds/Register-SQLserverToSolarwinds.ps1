function Register-SQLserverToSolarwinds{
    param (
        [Parameter(Mandatory=$True,HelpMessage="Choose the Solarwinds which exist")]
        [ValidateSet("solarwinds-reporting","solarwinds-central","solarwinds-spend","solarwinds-travel","solarwinds-test")]
        [String]$solarwinds,
        [Parameter(Mandatory=$True)]
        [String]$servername,
        [Parameter(Mandatory=$False,HelpMessage="Choose frorm existing VPC")]
        [ValidateSet("spend","travel","report","front","reportmigration","tools")]
        [String]$vpc
    )

    begin{
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy 
   
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
[System.Net.ServicePointManager]::CheckCertificateRevocationList = $null
[System.Net.ServicePointManager]::Expect100Continue = $null
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::SystemDefault

    }
    process
    {
        $env:https_proxy = ''
    
        $vault_namespace = 'tools/dbsql'
  
        switch ($env:aws_envt){
           "eu2"{ 
                $SqlPort = "2050"; 
                $awsRegion = 'eu-central-1';
                $fqdn = "$($vpc).cnqr.tech";
            break}
            "us2" { 
                $SqlPort = "2040"; 
                $awsRegion = 'us-west-2';
                $fqdn = "$($vpc).cnqr.tech";
            break}
            "integration" { 
                $SqlPort = "2020"; 
                $awsRegion = 'us-west-2';
                $fqdn = "$($env:aws_envt).system.cnqr.tech";
            break}
            "apj1" { 
                $SqlPort = "2060"; 
                $awsRegion = 'ap-northeast-1';
                $fqdn = "$($env:aws_envt).system.cnqr.tech";
            break}
        }
  
        
            set-location "C:\vault"
            . .\Get-VaultToken.ps1
            . .\Get-VaultPassword.ps1
            . .\Get-AdminPassword.ps1
            $token = Get-VaultToken -vault_namespace $vault_namespace -aws_region $awsRegion
            $secretName="$($solarwinds)-token"

            $Account = Get-VaultPassword -vault_namespace $vault_namespace -aws_region $awsRegion -Name "$($secretName)" -token $token
            $refreshToken = $Account.GetNetworkCredential().Password
            $PasswordSA = Get-AdminPassword -clusterName $($servername) -userAccount "sa" -VPC $vpc
            $userAccount = "solarwinds"
            $Account2 = Get-VaultPassword -vault_namespace $($vault_namespace) -aws_region $($awsRegion) -Name $($userAccount) -token $token
            $PasswordDPA = $Account2.GetNetworkCredential().Password

add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
[System.Net.ServicePointManager]::Expect100Continue = $false
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

        $baseURL = "https://$($solarwinds).tools.cnqr.tech/iwc/api/"
        $authTokenURL = "$($baseURL)security/oauth/token"
                        $body = @{"grant_type" = "refresh_token"
                                "refresh_token" = $refreshToken
                        };
                        try{
                                $dpaAuthResponse = Invoke-RestMethod -Uri $authTokenURL -Method POST -Body $body
                                if(!$dpaAuthResponse){
                                    throw "There was no response from the $($solarwinds) solarwinds server (url $($baseUrl)).  Please ensure this solarwinds $($solarwinds) is still monitoring server"
                                }
                                $tokenType = $DpaAuthResponse.token_type
                                $accessToken = $DpaAuthResponse.access_token
                                $dpaHeader = @{}
                                $dpaHeader.Add("Accept", "application/json")
                                $dpaHeader.Add("Content-Type", "application/json;charset=UTF-8")
                                $dpaHeader.Add("Authorization", "$tokenType $accessToken")
                            }
                            catch{
                            $_
                            write-output "Access Token Retrival Failed"
                            }
                    
                #----------------------------------------------------------
                # Register a SQL Server database instance for monitoring.
                #----------------------------------------------------------
                write-host "$($servername).$($fqdn)-$($PasswordDPA)-$($PasswordSA)"
                $registrationURL = $baseURL + "databases/register-monitor"
                $body = @{"databaseType" = "SQLSERVER";
                        "serverName" = "$($servername).$($fqdn)";
                        "port" = "$($SqlPort)";
                        "sysAdminUser" = "sa";
                        "sysAdminPassword" = "$($PasswordSA)";
                        "monitoringUser" = "solarwinds"
                        "monitoringUserPassword" = "$($PasswordDPA)";
                        "monitoringUserIsNew" = $false;
                        "displayName" = "$($servername).$($fqdn)"} | ConvertTo-Json

                try{
                    Write-Host "Registering Database..."
                    $dpaResponseJSON = Invoke-RestMethod -Uri $registrationURL -Body $body -Method POST -Headers $dpaHeader -TimeoutSec 60
                    $dpaResponse = $dpaResponseJSON.data
                    $result=$dpaResponse | Format-Table -AutoSize
                    write-output "Registering $($servername).$($fqdn) to $($solarwinds).tools.cnqr.tech was SUCCESSFULL" -ForegroundColor Green
                }
                catch{
                    write-output "Registering $($servername).$($fqdn) to $($solarwinds).tools.cnqr.tech FAILED"
                    $_.Exception.ToString()
                }
    }
    end{

    }
} 


 
