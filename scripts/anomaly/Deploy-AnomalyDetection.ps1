 #Requires -RunAsAdministrator

 function Deploy-AnomalyDetection {

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true,Mandatory=$true)][string[]]$Servers,
        [Parameter(Mandatory=$false)][string]$s3BucketName = "integration-dbsql-rpl",
        [Parameter(Mandatory=$false)][string]$s3KeyPrefix = "anomaly"
    )
  
    try {
        
        Write-Output "========================="
        Write-Output "Deploy Anomaly Detection"
        Write-Output "========================="
  
        Write-Output "`r`nStart...`r`n"
  
        $pass = @{
          Object = [Char]8730
          ForegroundColor = 'Green'
          NoNewLine = $true
        }
  
        $fail = @{
          Object = 'X'
          ForegroundColor = 'Red'
          NoNewLine = $false
        }  
  
        #Get S3 folder and download to local folder
        Write-Host "> Downloading files from S3 " -NoNewline 
        $localFolder = "C:\Temp\anomaly"
  
        if (Test-Path $localFolder) {
            Remove-Item $localFolder -Recurse -Force
        }
  
        Read-S3Object -BucketName $s3BucketName -KeyPrefix $s3KeyPrefix -Folder $localFolder | Out-Null
        Write-Host @pass
  
        Write-Host "`r`n> Reading config file " -NoNewline
        $config = Get-Content -Raw "$localFolder\config.json" | ConvertFrom-Json
        $destinationFolder = ($config.scriptDirectory).replace(":","$")
        $taskName = $config.taskName
        $scriptDir = $config.scriptDirectory
        $scriptFile = "$($scriptDir)\$($config.scriptFile)"
        $interval = $config.jobIntervalMins
  
        if ($interval -lt 5) {
            throw 'Interval in configuration file must be set to >= 5 (minutes)' 
            return
        } 
  
        Write-Host @pass
  
        Write-Host "`r`n> Deploying...`r`n" 
  
        #Create Windows job on destination server
        $Servers | % {
            
            Write-Host "  $($_)" -ForegroundColor Cyan
  
            Write-Host "  - Testing connection " -NoNewline
            if (!(Test-Connection -ComputerName $_ -Quiet -Count 1)){
                Write-Host "!" -ForegroundColor Yellow 
                Write-Warning "`Could not connect to $($_)" 
                return                       
            }
            Write-Host @pass
  
            #Copy files to destination server
            Write-Host "`r`n  - Copying files to destination server " -NoNewline
            $destination = "\\$($_)\$($destinationFolder)"
            New-Item $destination -Force -Type Directory  | Out-Null
            $exclude = @($MyInvocation.MyCommand.Name)
            Copy-Item "$($localFolder)\*" $destination -Exclude "$($exclude).ps1" -Recurse -Force -Confirm:$false | Out-Null
            Write-Host @pass
  
            Write-Host "`r`n  - Connecting to Server " -NoNewline
            Invoke-Command -ComputerName $_ -Scriptblock {
                
              try {
                  Write-Host @using:pass
  
                  #Check for existing tasks, recreate if already exsists
                  Write-Host "`r`n  - Checking if job $($using:taskName) already exists " -NoNewline
                  $getTask  = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:taskName } -ErrorAction Stop
                  Write-Host @using:pass
  
                  #Remove existing task if exists
                  if ($getTask) {
                      Write-Host "`r`n  - Removing existing job $($using:taskName) " -NoNewline
                      Unregister-ScheduledTask -TaskName $using:taskName -TaskPath $getTask.TaskPath -Confirm:$false -ErrorAction Stop
                      Write-Host @using:pass
  
                  }
  
                  #Register new job
                  Write-Host "`r`n  - Registering new job $($using:taskName) " -NoNewline
                  $jobInterval = New-TimeSpan -Minutes $using:interval -ErrorAction Stop
                  $startHour = (Get-Date).AddSeconds(60 -(Get-Date).Second).AddMinutes(59-(Get-Date).Minute % 60) 
                  $actions = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $using:scriptFile -ErrorAction Stop
                  $trigger = New-ScheduledTaskTrigger -Once -At $startHour -RepetitionInterval $jobInterval -ErrorAction Stop
                  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -ErrorAction Stop
                  $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest -ErrorAction Stop
                  $task = New-ScheduledTask -Action $actions -Trigger $trigger -Settings $settings -Principal $principal -ErrorAction Stop
  
                  Register-ScheduledTask -TaskName $using:taskName -InputObject $task -User "System" -ErrorAction Stop | Out-Null
                  Write-Host @using:pass
                  Write-Host "`r`n"
              }
  
              catch {
                  Write-Host @using:fail
                  Write-Host "`r`n  $($_)`r`n" -ForegroundColor Red
              }
  
            } 
  
        }
  
    }
  
    catch {
          Write-Host @fail
          Write-Host "`r`n$($_)`r`n" -ForegroundColor Red         
    }
  
    finally {
        Write-Host "End"
    }
  
  }     