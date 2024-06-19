function Update-TaskTime {
    
    try {
        $global:err = $null
       
        Write-Output "================="
        Write-Output "Update Task Time"
        Write-Output "================="

        Write-Output "`r`nStart...`r`n"

        #Update config   
        Write-Output "> Checking for config updates" 

        #Read config
        Write-Output "> Reading config"
        $configFile = "$PSScriptRoot\config.json"
        $config = Get-Content -Raw $configFile | ConvertFrom-Json
        $taskName = $config.taskName
        $scriptDir = $config.scriptDirectory
        $interval = New-TimeSpan -Minutes $config.jobIntervalMins

        #Check for existing tasks, recreate if already exsists
        Write-Output "> Retrieving existing task"  
        $getTask  = Get-ScheduledTaskInfo -TaskName $taskName

        if ($getTask) {

            #Check config updates
            Write-Output "> Checking for config updates"
            $taskRunTime = $getTask.NextRunTime - $getTask.LastRunTime 
            $taskRunInterval = [math]::Round($taskRunTime.TotalMinutes)

            if ($taskRunInterval -ne $config.jobIntervalMins) {        
                Write-Output "`r`n  - New config changes found `r`n"

            } else {
                Write-Output "`r`n  - No changes in config file"
                return
            }

            Write-Output "> Updating task time" 
            $startHour = (Get-Date).AddSeconds(60 -(Get-Date).Second).AddMinutes(59-(Get-Date).Minute % 60)
            $trigger = New-ScheduledTaskTrigger -Once -At $startHour -RepetitionInterval $interval
            Set-ScheduledTask -TaskName $taskName -Trigger $trigger | Out-Null
            Write-Output "`r`n  - Job interval changed from $($taskRunInterval) to $($config.jobIntervalMins)"     
        } else {          
            Write-Output "`r`n  - Cannot locate Windows task"
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