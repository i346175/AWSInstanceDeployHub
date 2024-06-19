<#
    MSSQL Cluster Builder
    - Creates new cluster on master node
    - Adds a scheduled task that uses sa account as its <run as> user
    - Runs scheduled task
    - Checks scheduled status and updates logs
#>

function Main {
    $hostIP = (Get-NetIPConfiguration).IPv4Address.IPAddress
    # read the cluster node address file for ips
    & C:\cfn\temp\get_cluster_nodes_addresses.ps1
    if ($hostIP -eq $MasterPrivateIP) { # the code to build cluster only runs on master node
        Write-Output ("Running on Master Node!") | Out-File -Append $logFile
        Add-ScheduledTask
        Write-Output ("Starting scheduled task [$TaskName] at: $(Get-Date -format 'u') ...") | Out-File -Append $logFile
        Start-ScheduledTask -TaskName $TaskName
        Write-Output ("Scheduled task [$TaskName] started.") | Out-File -Append $logFile
        Write-Output ("Started checking status of scheduled task: [$TaskName] at: $(Get-Date -format 'u')") | Out-File -Append $logFile
        $taskStatus = Check-ScheduledTaskStatus
        Disable-ScheduledTask
        Write-Output ("Completed checking status of scheduled task: [$TaskName] at: $(Get-Date -format 'u')") | Out-File -Append $logFile
        Write-Output ("Scheduled Task [$TaskName] status returned: [$taskStatus]") | Out-File -Append $logFile
    } else {
        Write-Output ("Running on a Worker Node!" ) | Out-File -Append $logFile
        Write-Output ("Not executing code to create cluster") | Out-File -Append $logFile
        Write-Output ("See master node for cluster build logs") | Out-File -Append $logFile
    }
}

function Add-ScheduledTask {
    $Global:TaskName = "NewClusterTask"
    Write-Output ("Started adding scheduled task: [$TaskName] at: $(Get-Date -format 'u')") | Out-File -Append $logFile
    ##################
    # run new cluster code as sa_dba_prov via the scheduled task
    ##################
    # Test to see if the task already exists.
    $TaskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $TaskName }
    # If it exists then drop it.
    if ($TaskExists) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$False
    }
    #build action
    $Execute = 'Powershell.exe'
    $CommandToBeRunInJob = "C:\mssql-scripts\build_cluster_via_sch_task_domainless.ps1 -taskName '$TaskName' -clusterName '$StackName' -region '$Region' -proxy '$Proxy' -phzname '$R53PHZName' -environment '$Environment' -logFile '$logFile'"
    $Argument = "-NoProfile -executionpolicy unrestricted -WindowStyle Hidden -NonInteractive -command &{$CommandToBeRunInJob}"
    $action = New-ScheduledTaskAction -Execute $Execute -Argument $Argument
    $trigger =  New-ScheduledTaskTrigger -AtStartup

    # use ClusAdmin as <run as> user
    $usrAccnt = "$env:COMPUTERNAME\ClusAdmin"

    # register task
    (Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description "Task used to create cluster" -User $usrAccnt -Password $ClusAdminPwd) | Out-File -Append $logFile

    $taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if($taskExists.TaskName -eq $TaskName) {
        Write-Output ("Completed registering task at: $(Get-Date -format 'u')" ) | Out-File -Append $logFile
        Write-Output ("Scheduled Task [$TaskName] created!" ) | Out-File -Append $logFile
    } else {
        Write-Output ("Scheduled Task [$TaskName] was not created!") | Out-File -Append $logFile
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
