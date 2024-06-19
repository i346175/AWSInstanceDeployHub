<#
    - Adds new node to WSFC cluster
    - Adds a scheduled task that uses sa account as its <run as> user
    - Runs scheduled task
    - Checks scheduled status and updates logs
#>


function Main {
    Set-Environment
    Write-Output (Format-LogMessage(">>>>>>>>>>>> Started Adding new node to WSFC Cluster at: $(Get-Date -format 'u') >>>>>>>>>>>>")) | Out-File -Append $logFile
    Add-ScheduledTask
    Write-Output (Format-LogMessage("Starting scheduled task [$TaskName] at: $(Get-Date -format 'u') ...")) | Out-File -Append $logFile
    Start-ScheduledTask -TaskName $TaskName
    Write-Output (Format-LogMessage("Scheduled task [$TaskName] started.")) | Out-File -Append $logFile
    Write-Output (Format-LogMessage("Started checking status of scheduled task: [$TaskName] at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
    $taskStatus = Check-ScheduledTaskStatus
    Disable-ScheduledTask
    Write-Output (Format-LogMessage("Completed checking status of scheduled task: [$TaskName] at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
    Write-Output (Format-LogMessage("Scheduled Task [$TaskName] status returned: [$taskStatus]")) | Out-File -Append $logFile
    Write-Output (Format-LogMessage(">>>>>>>>>>>> Completed Adding new node to WSFC Cluster at: $(Get-Date -format 'u') >>>>>>>>>>>>")) | Out-File -Append $logFile
}


function Set-Environment {
    try {
        $Global:mssqlScriptsFolder="C:\mssql-scripts"
        & $mssqlScriptsFolder\send_logs.ps1
        $Global:logsFolder = "$mssqlScriptsFolder\add_node_to_wsfc_cluster_logs"
        $timestamp = [int](Get-Date -UFormat %s -Millisecond 0)
        $Global:logFile = "$logsFolder\add_node_to_wsfc_cluster_log_$timestamp.log"
        if ((Test-Path $logsFolder) -eq $false) {
            New-Item -ItemType "directory" -Path $logsFolder
        }
        $TimeNow = Get-Date
        Write-Output (Format-LogMessage("Add node to cluster script ran at $TimeNow")) | Out-File -Append $logFile
    } catch {
        Write-Output (Format-LogMessage("Set-Environment failed.")) | Out-File -Append $logFile
        (Format-LogMessage($_)) | fl -Force | Out-File -Append $logFile
        throw "See $logFile for details."
    }
}


function Add-ScheduledTask {
    $Global:TaskName = "AddNodeToClusterTask"
    Write-Output (Format-LogMessage("Started adding scheduled task: [$TaskName] at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
    ##################
    # run add node to cluster code as sa_dba_prov via the scheduled task
    ##################
    # Test to see if the task already exists.
    $TaskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $TaskName }
    # If it exists then drop it.
    if ($TaskExists) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$False
    }
    #build action
    $Execute = 'Powershell.exe'
    $CommandToBeRunInJob = "C:\mssql-scripts\add_node_to_cluster_via_sch_task.ps1 -taskName '$TaskName' -clusterName '$StackName' -region '$Region' -proxy '$Proxy' -logFile '$logFile' -roletype '$RoleType'"
    $Argument = "-NoProfile -executionpolicy unrestricted -WindowStyle Hidden -NonInteractive -command &{$CommandToBeRunInJob}"
    $action = New-ScheduledTaskAction -Execute $Execute -Argument $Argument
    $trigger =  New-ScheduledTaskTrigger -AtStartup
    # use sa as <run as> user
    $usrAccnt = "$env:userdomain\sa_dba_prov"
    Write-Output (Format-LogMessage("Started restore $usrAccnt creds at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
    $sa_cred = (& C:\mssql-scripts\get_secrets.ps1)
    $saPwd = ($sa_cred.SA.password) | Out-String
    $saPwd = $saPwd.trim()
    Write-Output (Format-LogMessage("Completed restore sa creds at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
    Write-Output (Format-LogMessage("Started registering task at: $(Get-Date -format 'u')")) | Out-File -Append $logFile
    (Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description "Task used to create cluster" -User $usrAccnt -Password $saPwd) | Out-File -Append $logFile

    $taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if($taskExists.TaskName -eq $TaskName) {
        Write-Output (Format-LogMessage("Completed registering task at: $(Get-Date -format 'u')" ))| Out-File -Append $logFile
        Write-Output (Format-LogMessage("Scheduled Task [$TaskName] created!" ))| Out-File -Append $logFile
    } else {
        Write-Output (Format-LogMessage("Scheduled Task [$TaskName] was not created!")) | Out-File -Append $logFile
        throw "Add-ScheduledTask MSSQL function Error! See $logFile for details"
    }
}

function Check-ScheduledTaskStatus {
    $iterations = 65
    $sleepTime = 60
    $counter = 0
    $returnVal = ""
    do {
        $counter++
        $result = (Get-ScheduledTask -TaskName $TaskName | select taskname, state)
        $result = $result | Out-String
        if ($result -like "*Running*") {
            $returnVal = 'Running'
        } elseif ($result -like "*Ready*") {
            $returnVal = 'Completed'
            break
        } else {
            $returnVal = "Failed"
            # Exit the loop now since the job has probably failed
            break
        }
        Start-Sleep -s $sleepTime
    } while ($counter -le $iterations)
    # Handle if the job is still running after the given time window
    if ($counter -gt $iterations) {
        $returnVal = "TimedOut"
    }
    # Return the status of the task
    $returnVal
}

function Disable-ScheduledTask {
    $service = new-object -ComObject("Schedule.Service")
    $service.Connect()
    $rootFolder = $service.GetFolder("\")
    $task = $rootFolder.GetTask($taskName)
    $task.enabled = $false
}

Main