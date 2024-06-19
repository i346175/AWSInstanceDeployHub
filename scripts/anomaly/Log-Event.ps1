function Log-Event {
    [CmdletBinding()]
    param (   
        [Parameter(Mandatory,ValueFromPipeline,Position=0)][string]$Event,
        [Parameter(Mandatory,ValueFromPipeline)][string]$EventSource,
        [string]$LogName = "Anomaly Detection"
    )

    if (![System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName $LogName -Source $EventSource 
    }    

    #Check for errors
    if ($err -ne $null) {  
        Write-EventLog -LogName $LogName -EntryType Error -EventId 0 -Source $EventSource -Message $Event
        
        #Notify for errors
        $snsTopic = "IOPS-DB-Slack"
        $accountDetails = Get-EC2InstanceMetadata -Category IdentityDocument | ConvertFrom-Json | Select accountId, region
        $awsPartition = (Get-EC2InstanceMetadata -Category Region).PartitionName
        $snsArn = "arn:$($awsPartition):sns:$($accountDetails.region):$($accountDetails.accountID):$($snsTopic)"
        Publish-SNSMessage -TopicArn $snsArn -Subject "[$(($env:USERDOMAIN).ToUpper())] $($env:COMPUTERNAME): ERROR in $($LogName) - $($EventSource)" -Message "Please investigate the following error in $($LogName) - $($EventSource) `r`n`r`n  $Event" | Out-Null

    } else {
        Write-EventLog -LogName $LogName -EntryType Information -EventId 1 -Source $EventSource -Message $Event
    }
}    
