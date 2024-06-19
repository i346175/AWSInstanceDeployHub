function Log-Anomaly {
    <#
        .SYNOPSIS
        Logs Transaction Anomalies

        .DESCRIPTION
        Compares 2 samples of number of Transactions/sec.
        If transactions have increased by x percent and increased by a minimum number of n transactions, then log to file for Splunk ingestion.
        Cleanup old files based on retention.

        .PARAMETER ShowThresholds
        Optional switch to show threholds.

        .PARAMETER ComputeValues
        Optional switch to input 2 values to detect if an anomaly will be detected.
        This will also explain how anomaly detection works.

        .PARAMETER Output
        Optional switch to show output of any anomalies detected.

        .NOTES
        Author: Shamile Fiaz 
        Version: 1.11

    #>
    [CmdletBinding(PositionalBinding=$false)]
    param (  
        [switch]$ShowThresholds,
        [int[]] $ComputeValues,
        [switch]$Output     
    )
   
    try {     
        $global:err = $null
       
        Write-Output "============"
        Write-Output "Log Anomaly"
        Write-Output "============"

        Write-Output "`r`nStart...`r`n"

        #Read config
        Write-Output "> Reading config"
        
        $configFile = "$PSScriptRoot\config.json"
        $config = Get-Content -Raw $configFile | ConvertFrom-Json
        
        #Update config   
        Write-Output "> Checking for config updates"    
        $s3BucketName = $config.s3BucketName
        $s3Key = $config.s3Key
        $s3Region =  Get-EC2InstanceMetadata -Category IdentityDocument | ConvertFrom-Json | Select-Object -ExpandProperty region
        $updateMins = $config.s3UpdateMins

        $s3Date = Get-S3ObjectMetadata -BucketName $s3BucketName -Key $s3Key -Region $s3Region -Select LastModified

        if ((((Get-Date).ToUniversalTime()) - $s3Date) -le (New-TimeSpan -Minutes $updateMins)) {
            Write-Output "`r`n  - Downloading file from S3..."
            Read-S3Object -BucketName $s3BucketName -Key $s3Key -Region $s3Region -File $configFile | Out-Null
            Write-Output "  - File downloaded.`r`n"
            $config = Get-Content -Raw $configFile | ConvertFrom-Json
        }

        #Set Variables
        $counter = "\SQLServer:Databases(*)\Transactions/sec"
        $threshold = $config.threshold
        $splunkDirectory = $config.splunkDirectory
        $splunkRetentionDays = $config.splunkRetentionDays
        $baseSampleFile = $config.baseSampleFile
        $exclude = $config.exclude
        $loggedValues = [PSCustomObject]@()
        $testValues = [PSCustomObject]@()
        $thresholdPercentage = 0
        $min = 0
        $interval = $config.jobIntervalMins
        $fileDate = Get-Date -Format yyyy_MM_dd_HHmm
        $runDate =  Get-Date -UFormat "%m-%d-%Y %R:%S %Z" 
 
        Write-Output "> Retrieving thresholds"

        for ($t=0; $t -lt @($threshold.PsObject.Properties).count; $t++) {
            if ($t -ne 0) {                 
                if ($($threshold.($t - 1)).upperBound -ne $($threshold.($t)).lowerBound) {                 
                    Write-Output "`r`n  - Config file not configured correctly."
                    Write-Output "`r`n  Threshold $($t - 1) upperBound Value ($(($threshold.($t - 1)).upperBound)) must be the same value as Threshold $($t) lowerBound value ($(($threshold.($t)).lowerBound))"
                    throw
                }
                $minTransactions = [math]::Round(($($threshold.($t - 1)).percentage / 100) * $($threshold.($t - 1)).upperBound)                                      
            } else {
                $minTransactions = [math]::Round(($($threshold.($t)).percentage / 100) * $($threshold.($t)).lowerBound) 
            }
            $threshold.$($t) | Add-Member -NotePropertyName minimum -NotePropertyValue $minTransactions
        }

        #For switch ShowThresholds
        if ($ShowThresholds) {
            Write-Output $threshold.PsObject.Properties | Select-Object -ExpandProperty Value
            return
        }

        #For switch ShowThresholds - shows whether an anomaly will be detected
        if ($ComputeValues) {
            Write-Output "> Computing Test Values"

            if ($ComputeValues.Count -ne 2) {
                Write-Output "`r`n  - Oops..there must be 2 int values provided"
                return
            }

            if ($ComputeValues[1] -le $ComputeValues[0]) {
                Write-Output "`r`n  - Oops...second value must be higher than first!"
                return
            }         

            #Get percentage & minimum thresholds 
            for ($s=0; $s -lt @($threshold.PsObject.Properties).count; $s++) {                
                if ($ComputeValues[0] -ge ($threshold.$s).lowerBound -and $ComputeValues[0] -le ($threshold.$s).upperBound) {                     
                    $thresholdPercentage = ($threshold.$s).percentage
                    $min = $($threshold.$s).minimum
                    $thresholdNo = $s
                    $lowerBound = ($threshold.$s).lowerBound
                    $upperBound = ($threshold.$s).upperBound
                } 
              }
               
            #Get percentage difference between 2 totals
            $diff = $ComputeValues[1] - $ComputeValues[0] 
            $perDiff = [math]::Round(($diff / $ComputeValues[0])  * 100)

            #TODO: put the verbose in another function in the future - it's messy!
            if ($thresholdPercentage -eq 0) {
                Write-Host "`r`n  - No anomaly will be detected" -BackgroundColor DarkYellow
                Write-Host "`r`n1. Transaction values increased from $($ComputeValues[0]) to $($ComputeValues[1]). " 
                Write-Host "`r`n2. This is a percentage increase of " -NoNewline
                Write-Host "$($perDiff)" -ForegroundColor Cyan -NoNewline
                Write-Host " and the number of transactions increased by " -NoNewline
                Write-Host "$($diff)" -ForegroundColor Cyan -NoNewline
                Write-Host "."
                Write-Host "`r`n3. This will NOT fall under any configurational threshold as the first sample transactions (" -NoNewline
                Write-Host "$($ComputeValues[0])" -ForegroundColor Cyan -NoNewline
                Write-Host ")" 
                Write-Host " is NOT between any of the LowerBound and the UpperBound values specified in the config file."
                Write-Host "[NOTE: Trivial number of transactions should be ignored regardless of how much they increase by as results will be unexpected]" -ForegroundColor DarkGray
                return
            } 
                 
            $testValues = [PSCustomObject]@{
                ConfigNumber = $thresholdNo
                LowerBound = $lowerBound
                UpperBound = $upperBound
                Minimum = $min
                Percent = $thresholdPercentage           
            }
            
            #TODO: put the verbose in another function in the future - it's messy!
            if ($diff -ge $min -and $perDiff -ge $thresholdPercentage) {                   
                Write-Host "`r`n  - Anoamly will be detected" -BackgroundColor DarkGreen
                Write-Host "`r`n1. Transaction values increased from $($ComputeValues[0]) to $($ComputeValues[1]). " 
                Write-Host "`r`n2. This is a percentage increase of " -NoNewline
                Write-Host "$($perDiff)" -ForegroundColor Cyan -NoNewline
                Write-Host " and the number of transactions increased by " -NoNewline
                Write-Host "$($diff)" -ForegroundColor Cyan -NoNewline
                Write-Host "."
                Write-Host "`r`n3. This will fall under the following configuration as the first sample transactions (" -NoNewline
                Write-Host "$($ComputeValues[0])" -ForegroundColor Cyan -NoNewline
                Write-Host ")"
                Write-Host " is between the LowerBound (" -NoNewline
                Write-Host "$($lowerBound)" -ForegroundColor Cyan -NoNewline
                Write-Host ") and the UpperBound (" -NoNewline
                Write-Host  "$($upperBound)"  -ForegroundColor Cyan -NoNewline
                Write-Host ") values."
                Write-Output $testValues | Format-List -Property ConfigNumber, LowerBound, UpperBound, Minimum, Percent
                Write-Host "4. As seen above, the threshold percent for this configuration is " -NoNewLine
                Write-Host "$($thresholdPercentage)" -ForegroundColor Cyan -NoNewline
                Write-Host " and minimum number of transactions is " -NoNewline
                Write-Host "$($min)" -ForegroundColor Cyan -NoNewline
                Write-Host "."
                Write-Host "[NOTE: the minimum value is not in the config but is calculated as the percentage value of the previous config upperBound value]" -ForegroundColor DarkGray
                Write-Host "`r`n5. Therefore since...`r`n"
                Write-Host "a) the transaction percentage increase of " -NoNewline
                Write-Host "$($perDiff)" -ForegroundColor Cyan -NoNewline
                Write-Host " is greater or equal than the percent value specified in the config (Percent:" -NoNewline
                Write-Host "$($thresholdPercentage)" -ForegroundColor Cyan -NoNewline
                Write-Host ")"
                Write-Host "`r`nAND `r`n"
                Write-Host "b) the number of transactions increased " -NoNewline
                Write-Host "$($diff)" -ForegroundColor Cyan -NoNewline
                Write-Host " is greater or equal than the minimum value specified in the config (Minimum:" -NoNewline
                Write-Host "$($min)" -ForegroundColor Cyan -NoNewline
                Write-Host ")"
                Write-Host "`r`nThe anomaly gets logged!"
                Write-Host "`r`nThis can be summed up in the following formula:"
                Write-Host "`r`n(PercentIncreased >= ConfigPercent) && (NumberIncrease >= Minimum)" -ForegroundColor Yellow 
            } else {
                Write-Host "`r`n  - No anomaly will be detected" -BackgroundColor DarkYellow
                Write-Host "`r`n1. Transaction values increased from $($ComputeValues[0]) to $($ComputeValues[1]). " 
                Write-Host "`r`n2. This is a percentage increase of " -NoNewline
                Write-Host "$($perDiff)" -ForegroundColor Cyan -NoNewline
                Write-Host " and the number of transactions increased by " -NoNewline
                Write-Host "$($diff)" -ForegroundColor Cyan -NoNewline
                Write-Host "."
                Write-Host "`r`n3. This will fall under the following configuration as the first sample transactions (" -NoNewline
                Write-Host "$($ComputeValues[0])" -ForegroundColor Cyan -NoNewline
                Write-Host ")"
                Write-Host " is between the LowerBound (" -NoNewline
                Write-Host "$($lowerBound)" -ForegroundColor Cyan -NoNewline
                Write-Host ") and the UpperBound (" -NoNewline
                Write-Host  "$($upperBound)"  -ForegroundColor Cyan -NoNewline
                Write-Host ") values."
                Write-Output $testValues | Format-List -Property ConfigNumber, LowerBound, UpperBound, Minimum, Percent
                Write-Host "4. As seen above, the threshold percent for this configuration is " -NoNewLine
                Write-Host "$($thresholdPercentage)" -ForegroundColor Cyan -NoNewline
                Write-Host " and minimum number of transactions is " -NoNewline
                Write-Host "$($min)" -ForegroundColor Cyan -NoNewline
                Write-Host "."
                Write-Host "[NOTE: the minimum value is not in the config but is calculated as the percentage value of the previous config upperBound value]" -ForegroundColor DarkGray
                Write-Host "`r`n5. Therefore since...`r`n"
                Write-Host "a) the transaction percentage increase of " -NoNewline
                Write-Host "$($perDiff)" -ForegroundColor Cyan -NoNewline
                Write-Host " is NOT greater or equal than the percent value specified in the config (Percent:" -NoNewline
                Write-Host "$($thresholdPercentage)" -ForegroundColor Cyan -NoNewline
                Write-Host ")"
                Write-Host "`r`nOR `r`n"
                Write-Host "b) the number of transactions increased " -NoNewline
                Write-Host "$($diff)" -ForegroundColor Cyan -NoNewline
                Write-Host " is NOT greater or equal than the minimum value specified in the config (Minimum:" -NoNewline
                Write-Host "$($min)" -ForegroundColor Cyan -NoNewline
                Write-Host ")"
                Write-Host "`r`nThe anomaly DOES NOT get logged!"
                Write-Host "`r`nThis can be summed up in the following formula:"
                Write-Host "`r`n(PercentIncreased < ConfigPercent) || (NumberIncrease < Minimum)" -ForegroundColor Yellow
            }
            return
        }
        
        #Get SQL Service
        Write-Output "> Checking SQL Service is running"

        if ((Get-Service -Name MSSQLServer).Status -ne "Running") {
            Write-Output "`r`n  - SQL Service is not running"
            return 
        }

        #Get/Create base sample
        Write-Output "> Checking if base sample exists"

        if (!(Test-Path -Path $baseSampleFile -PathType Leaf)) {
            Get-Counter $counter | ConvertTo-Json | Out-File (New-Item -Path $baseSampleFile -Force)
            Write-Output "`r`n - Base sample file created. Anomaly will be analysed on next run."
            return
        } else {
            Write-Output "> Retrieving base sample data"
            $baseSample = Get-Content $baseSampleFile | ConvertFrom-Json | Select-Object -Expand CounterSamples
        }

        #Collect new sample
        Write-Output "> Collecting new sample" 

        Get-Counter $counter | ConvertTo-Json | Out-File $baseSampleFile
        $newSample = Get-Content $baseSampleFile | ConvertFrom-Json | Select-Object -Expand CounterSamples 

        #Get list of databases & total sample (exclude sys databases)
        Write-Output "> Filtering new sample "

        $instance = $newSample | Where-Object {$_.InstanceName -notin $exclude} | Select InstanceName | Sort-Object InstanceName | Get-Unique -asString

        Write-Output "> Checking anomaly for each database & total `r`n"

        foreach ($i in $instance) {           
            [array]$records = $baseSample | Where-Object { $_.InstanceName -eq $i.InstanceName} | Sort-Object -Property TimeStamp | Select TimeStamp, InstanceName, CookedValue
            [array]$records += $newSample | Where-Object { $_.InstanceName -eq $i.InstanceName} | Sort-Object -Property TimeStamp | Select TimeStamp, InstanceName, CookedValue

            $baseSampleValue = [math]::Round($records[0].CookedValue)
            $newSampleValue = [math]::Round($records[1].CookedValue)

            #Check if there are 2 records to compare per database, & at least 1 transaction recorded & higher number of transations in the new value recorded         
            if (($records.Count) -eq 2 -and $baseSampleValue -gt 1 -and $newSampleValue -gt $baseSampleValue) {  
                              
                #Get percentage & minimum thresholds 
                for ($x=0; $x -lt @($threshold.PsObject.Properties).count; $x++) {                
                    if ($baseSampleValue -ge $($threshold.$x).lowerBound -and $baseSampleValue -lt $($threshold.$x).upperBound) {                      
                        $thresholdPercentage = $($threshold.$x).percentage
                        $min = $($threshold.$x).minimum
                    } 
                }

                if ($thresholdPercentage -eq 0) {
                    continue
                }

                #Get percentage difference between 2 totals
                $diff = $newSampleValue - $baseSampleValue
                $perDiff = ($diff / $baseSampleValue)  * 100

                #If increase between samples >minimum and percentage is >= threshold percentage then log values
                if ($diff -gt $min -and $perDiff -ge $thresholdPercentage) {                   
                    Write-Output "  - $($i.InstanceName): Anomaly Detected"

                    $loggedValues += [PSCustomObject]@{
                        Database = $i.InstanceName
                        PreviousTransactions = $baseSampleValue
                        NewTransactions = $newSampleValue
                        NumberOfTransactionsIncreased = [math]::Round($diff)
                        PercentageIncreased = [math]::Round($perDiff)
                    } 

                    if ($Output) {
                        $loggedValues[$loggedValues.Count - 1] | Write-Output | Format-List
                    }
                }
            }
        } 

        #Log anomaly to output file
        if ($loggedValues) {
            Write-Output "`r`n> Logging all detected anomalies for Splunk ingestion"
            $toSplunk += [PSCustomObject]@{
                        CreatedTime = $runDate
                        IntervalMins = $interval
                        Databases = $loggedValues               
                    } 
                    
            $toSplunk | ConvertTo-Json | Out-File  (New-Item -Path "$splunkDirectory\output_$($fileDate).json" -Force)
        } else {
            Write-Output "  - No anomaly detected `r`n"
        }

        # CLEANUP - Delete files older than the $logRetentionDays
        Write-Output "> Cleaning up files older than $($splunkRetentionDays) day(s)"

        if ($splunkDirectory -ne $null) {
            Get-ChildItem $splunkDirectory -Recurse -File | Where CreationTime -lt (Get-Date).AddDays(-$splunkRetentionDays) | Remove-Item -Force
        }
    }

    #Catch errors
    catch {       
        $global:err = $PSItem.Exception.Message
 
        Write-Output "`r`nERROR"
        Write-Output "------------------`r`n"
        Write-Output $err
        Write-Output "`r`n------------------"
    }

    finally {
        Write-Output "`r`nEnd"
    }
}
