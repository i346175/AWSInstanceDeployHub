
function log() {
    param (
     [string]$string = "",
     [string]$color,
     [bool]$quiet = $false
      )
        $logstring = ($(Get-Date).toString())+" : "+$string
        if(! $quiet)
            {
             if($color)
                {
                 Write-Host $logstring -BackgroundColor $color
                }
             else
                {
                 Write-Host $logstring
                }
            }
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\run_prebuild_scripts.log"
}

log "Started run_prebuild_scripts"
#Get time
$now = Get-Date
$now = $now.ToString("yyyy-MM-dd HH:mm:ss")
log "Current time is $now"

# snewman 20240529
function Enable-TagsInMetaData{
    param(

    )
    begin{

    }
    process{
        # IMDSv2
        $token = Invoke-RestMethod -Uri "http://169.254.169.254/latest/api/token" -Method Put -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = 120} -UseBasicParsing
        $headers = @{"X-aws-ec2-metadata-token" = $token}

        $instanceID = Invoke-WebRequest -Uri "http://169.254.169.254/latest/meta-data/instance-id" -UseBasicParsing -Headers $headers | Select-Object -ExpandProperty content
        log "InstanceID found:  $instanceID."
        log "enabing metadata tags"
        aws ec2 modify-instance-metadata-options --instance-id $instanceID --instance-metadata-tags enabled > $null;

        log "Polling for enabling of tags in metadata..."
        $result = aws ec2 describe-instances --instance-ids $instanceID | ConvertFrom-Json
        if($result.Reservations.Instances.MetadataOptions.InstanceMetadataTags -eq 'enabled'){
            return;
        } 

        $timer = [Diagnostics.Stopwatch]::StartNew();
        do{
            Start-Sleep -Seconds 3
            if($timer.Elapsed.TotalMinutes -gt 2){  # 2 minutes is not random...the token from above expires after 2 minutes...
                $timer.Stop();
                throw "There was a timeout waiting for the metatdata tags to be enabled for instance $instanceID (2 minutes)"
            }
            log "metadata tags not yet enabled; elapsed seconds: $($timer.TotalSeconds)"
            $result = aws ec2 describe-instances --instance-ids $instanceID | ConvertFrom-Json
        }until($result.Reservations.Instances.MetadataOptions.InstanceMetadataTags -eq 'enabled')
    }
    end{

    }
}

# snewman 20240529
function Get-TestBuild{
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$S3HomeDirectory
    )
    begin{

    }
    process{

        log "Getting TestBuild Tag Information"
        # $testBuildName = Invoke-WebRequest -Uri "http://169.254.169.254/latest/meta-data/tags/instance/TestBuild" -Headers $headers -UseBasicParsing -ErrorAction SilentlyContinue | Select-Object -ExpandProperty content
        # $IsValid = (![System.String]::IsNullOrWhiteSpace($testBuildName)) -and ($null -ne (aws s3 ls "$S3HomeDirectory/$testBuildName"));

        try{
            # IMDSv2
            $token = Invoke-RestMethod -Uri "http://169.254.169.254/latest/api/token" -Method Put -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = 60} -UseBasicParsing
            $headers = @{"X-aws-ec2-metadata-token" = $token}
            $testBuildName = Invoke-WebRequest -Uri "http://169.254.169.254/latest/meta-data/tags/instance/TestBuild" -Headers $headers -UseBasicParsing | Select-Object -ExpandProperty content
            $IsValid = (![System.String]::IsNullOrWhiteSpace($testBuildName)) -and ($null -ne (aws s3 ls "$S3HomeDirectory/$testBuildName"));
            log "TestBuild path:  $S3HomeDirectory/$testBuildName"
        }
        catch [System.Net.WebException]{
            if([int]$_.Exception.Response.StatusCode -eq 404){
                $IsValid = $false;
                $testBuildName = '';
            }
            else{
                throw $_;
            }
        } 

        return [PSCustomObject]@{
            TestBuildExists = $IsValid
            Name = $testBuildName 
            Path = "$S3HomeDirectory/$testBuildName"
        }
    }
    end{

    }
}


try{

    $env:http_proxy='';  #snewman 20240529 (the metadata calls are http...)   
    $camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig";
    # snewman | enable tags in metadata service & look for a tag named TestBuild
    $homeS3Dir = "s3://$($camConfig.s3BucketName)/$($camConfig.repository)/$($camConfig.scripts)"

    try{
        Enable-TagsInMetaData
        $build = Get-TestBuild -S3HomeDirectory $homeS3Dir
    }
    catch{
        log "Unhandled exception enabling metadata tags or getting test build info."
        log "Unhandled exception details:`n$($_ | Format-List -Force | Out-String)"
    }

    # snewman | Download the testBuild from S3 if it exists & extract replacing Concur.SqlBuild
    if($build.TestBuildExists){
        log "Downloading $($build.Name) from S3."
        aws s3 cp $build.Path "C:\\cfn\\Concur.SqlBuild.zip" --quiet
    }
    else{
        $buildExists = Get-Item "c:\cfn\Concur.SqlBuild.zip" -ErrorAction SilentlyContinue
        if(!$buildExists.name){
            log "Downloading Concur.SqlBuild from S3."
            aws s3 cp "$homeS3Dir/Concur.SqlBuild.zip" "C:\\cfn\\Concur.SqlBuild.zip" --quiet
        }
    }        
}
catch{
    log "Unhandled exception running the prebuild scripts."
    log "Unhandled exception details:`n$($_ | Format-List -Force | Out-String)"
}
finally{
    if(!(Test-Path -Path 'c:\cfn\Concur.SqlBuild.zip')){
        log "Concur.SqlBuild not found; downloading module from finally block."
        $camConfig = Get-ItemProperty "HKLM:\SOFTWARE\camConfig";
        # snewman | enable tags in metadata service & look for a tag named TestBuild
        $homeS3Dir = "s3://$($camConfig.s3BucketName)/$($camConfig.repository)/$($camConfig.scripts)"
        aws s3 cp "$homeS3Dir/Concur.SqlBuild.zip" "C:\\cfn\\Concur.SqlBuild.zip" --quiet
    }
}

