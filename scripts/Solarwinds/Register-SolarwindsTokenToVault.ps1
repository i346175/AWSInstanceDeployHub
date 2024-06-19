function Register-SolarwindsTokenToVault {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Choose the Solarwinds which exist")]
        [ValidateSet("solarwinds-reporting","solarwinds-central","solarwinds-spend","solarwinds-travel","solarwinds-test")]
        [String]$solarwinds
    )

    begin{
        . C:\vault\Set-VaultPassword.ps1
        . C:\vault\Get-VaultToken.ps1
        $env:https_proxy=''
    }
    process{
        try{
            #Get token for operation with Vault          
            $token=Get-VaultToken -aws_region  $env:aws_region -vault_namespace tools/dbsql        
            #Get the agreed format of Solarwinds DPA secretname
            $secretName = "$solarwinds-token"
          
            #Register token which you generated in Solarwinds DPA application
            $secret=read-host -AsSecureString -Prompt "Register new $($solarwinds) token in $($env:aws_envt)"
            [pscredential]$account = New-Object System.Management.Automation.PSCredential ("$secretName", $secret)
            Set-VaultPassword -vault_namespace tools/dbsql -aws_region $env:aws_region -Account $account -token $token
            write-Output "The $solarwinds token were stored to Vault with secretname $secretName for $($env:aws_envt)"             
        }
        catch{
             write-error -Message "Problem with setting new token value for specified $($solarwinds) in $($env:aws_envt)"
        }
        finally{

        }

    }
    end{

    }
}  
