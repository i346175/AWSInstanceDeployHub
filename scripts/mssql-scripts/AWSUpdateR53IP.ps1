using namespace Microsoft.SqlServer.Management.smo
using namespace Microsoft.SqlServer.Management.Common
#using namespace System.Collections.Generic
param(
$IP = $null,
$R53Name,
$hostedZoneID,
$TimeOutMinutes = 5
)

function Get-LocalListenerIP{
    param(

    )
    begin{
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
        [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    }
    process{

        try{
            #TODO:  Add a fallback 2nd try to get ip address if first call fails somehow...
            $srv = new-object Server '.'
            $srv.AvailabilityGroups[0].AvailabilityGroupListeners | %{
                $_.AvailabilityGroupListenerIPAddresses.IPAddress | %{
                    $ip = $_
                    return Get-NetIPAddress | ?{$_.AddressFamily -eq 'IPv4'} | ?{$_.IPAddress -eq $ip} | select -ExpandProperty IPAddress
                }
            }
        }
        catch{
            throw $_
        }
        finally{
            if($srv){
                $srv.ConnectionContext.Disconnect();
            }
        }

    }
    end{

    }
}

try{

    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

    New-EventLog -LogName Application -Source "AWSConcurAlwaysOn" -ErrorAction SilentlyContinue

    if([System.String]::IsNullOrWhiteSpace($IP)){
        $IP = Get-LocalListenerIP
    }

    #check if R53 name is currently already resolving to the current IP...
    $current = Resolve-DnsName -Name $R53Name
    if($current.IPAddress -eq $IP){
        Write-EventLog -LogName Application -Source "AWSConcurAlwaysOn" -EntryType Warning -EventID 100 -Message "Attempt to fail over $R53Name to IP $IP aborted, as $R53Name already resolves to ip address $IP."
        return;
    }

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $SuccessFlag = 1
    $RetryInterval = 10
    $Factor = 1
    $Expo = 2
    $Count=0
    while($SuccessFlag -ne 0){
        $env:https_proxy = 'proxy.service.cnqr.tech:3128'
        $resp = aws route53 change-resource-record-sets --hosted-zone-id $hostedZoneID --change-batch file://C:\cfn\UpdateDNSARecordforSQLList.json --no-verify-ssl
        Start-Sleep -Seconds ($RetryInterval * $Factor)
        $respObj = $resp | ConvertFrom-Json
        if($respObj.ChangeInfo.Status -eq "PENDING"){
            Write-Output "Successfully set R53 record for listener to point to [$env:COMPUTERNAME] secondary IPs." >>C:\cfn\logfile.txt
            $SuccessFlag = 0
            break
        }
        if($timer.Elapsed.TotalMinutes -gt $TimeOutMinutes){
            $timer.Stop();
            Write-Output "Attempt to set R53 record for listener aborted due to timeout." >>C:\cfn\logfile.txt
            break
        } else {
            $Factor = $Factor * $Expo
            $Count += 1
            Write-Output ("Attempting retry [$Count]... at: $(Get-Date -format 'u')") >>C:\cfn\logfile.txt
        }
    }

}
catch{
    $_ | fl -Force
    Write-EventLog -LogName Application -Source "AWSConcurAlwaysOn" -EntryType Error -EventID 300 -Message "Attempt to fail over $R53Name to IP $IP threw an exception:`r`n$($_ | Format-List -Force | Out-String)"

    # Create the JSON payload 
    $ErrorMessage = 'Error: {0}' -f $_.Exception.Message
    Write-Output $ErrorMessage
    $IP = $IP.ToString()

    $InputData = @{ subject = 'AWS Update R53 IP - ' + $R53Name + ' encountered an error' 
                       message = 'Attempt to fail over ' + $R53Name + ' to IP ' + $IP + ' threw an exception: ' + $ErrorMessage 
                       title = 'AWS Update R53 IP - ' + $R53Name + ' encountered an error' 
                       destination ='pagerduty'
                       notification_type = 'critical'
                    } | ConvertTo-Json

    # Invoke the MSSQLLambda-SendNotification Lambda function to send notification to IOPS-DBA pagerduty 
    $Result = Invoke-LMFunction -FunctionName MSSQLLambda-SendNotification -Payload $InputData 

}
