



# Example PowerShell script to domain join a Windows instance securely
$ErrorActionPreference = 'Stop'
# Importing proxy as its needed to get SSM parameter store values since SSM endpoint is not workgin as expected
netsh winhttp import proxy source=ie
(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
$scripts = "C:\cfn\Temp"
$instance = wget http://169.254.169.254/latest/dynamic/instance-identity/document -UseBasicParsing | ConvertFrom-Json 
# Retrieve Account-ID / Instance-ID of the running instance
$acct_id = $instance.accountId
$inst_id = $instance.instanceId 
# Check to see if the id matches the environment
$accounts = Get-Content $scripts\accounts.json | ConvertFrom-Json
$aws_account_id = ""
$aws_env = ""
$aws_acct_name= ""
foreach($line in $accounts.accounts){
  if($line.id -eq $acct_id) { 
        $aws_account_id = $line.id
        $aws_env = $line.env
        if($aws_env -eq "apj1" -and $aws_account_id -eq "866971198914") { 
          $aws_acct_name = "frontend"
        }
        else {
          $aws_acct_name = $line.name
        }     
  }
}

### 
try{
$domain = '<DomainSuffix>'
if ($aws_env -eq "apj1"){
$username = $domain + '\' + (Get-SSMParameterValue -Name username).Parameters[0].Value
$password = (Get-SSMParameterValue -Name password -WithDecryption $True).Parameters[0].Value | ConvertTo-SecureString -asPlainText -Force
}
else {
  . C:\vault\Get-VaultToken.ps1
  . C:\vault\Get-VaultPassword.ps1
  $scripts = "C:\cfn\Temp"
  $username = $domain + '\<ProvisioningAccount>'
  $env:https_proxy = ''
  $vault_namespace = '<VaultNamespace>'
  $aws_region = '<awsRegion>'
  $token = Get-VaultToken -vault_namespace $vault_namespace -aws_region $aws_region
  $Secret = Get-VaultPassword -Name '<ProvisioningAccount>' -token $token -vault_namespace $vault_namespace -aws_region $aws_region
  $password = ConvertTo-SecureString -String $($Secret.GetNetworkCredential().Password) -asPlainText -Force
}

# Create a System.Management.Automation.PSCredential object
$credential = New-Object System.Management.Automation.PSCredential($username, $password)
$oupath_integ = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=INTEGRATION,DC=integration,DC=system,DC=cnqr,DC=tech"
$oupath_pscc = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=USPSCC,DC=uspscc,DC=system,DC=cnqr,DC=tech"
$oupath_us2 = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=us2,DC=us2,DC=system,DC=cnqr,DC=tech"
$oupath_eu2 = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=eu2,DC=eu2,DC=system,DC=cnqr,DC=tech"
$oupath_fabian_us = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=fabian-us,DC=fabian-us,DC=system,DC=cnqr,DC=tech"
$oupath_fabian_emea = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=fabian-emea,DC=fabian-emea,DC=system,DC=cnqr,DC=tech"
$oupath_apj1 = "OU=$aws_acct_name,OU=Infrastructure,OU=Servers,OU=apj1,DC=apj1,DC=system,DC=cnqr,DC=tech"
# Join the domain and reboot
if (!((Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain)){
echo "joining $domain"
  if($aws_env -eq "integration"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_integ -Restart -Force
  }
  elseif($aws_env -eq "uspscc"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_pscc -Restart -Force
  }
  elseif($aws_env -eq "us2"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_us2 -Restart -Force
  }
  elseif($aws_env -eq "eu2"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_eu2 -Restart -Force
  }
  elseif($aws_env -eq "fabian-us"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_fabian_us -Restart -Force
  }
  elseif($aws_env -eq "apj1"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_apj1 -Restart -Force
  }
  elseif($aws_env -eq "fabian-emea"){
    Add-Computer -DomainName $domain -Credential $credential -oupath $oupath_fabian_emea -Restart -Force
  }
else{echo "already joined to $domain"}
}
}
catch [Exception]{
Write-Host $_.Exception.ToString()
Write-Host Command execution failed.
$host.SetShouldExit(1)
}
