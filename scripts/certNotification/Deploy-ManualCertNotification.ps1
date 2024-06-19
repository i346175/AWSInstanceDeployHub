#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

function Deploy-ManualCertNotification{
    ###############################################################
    # Input Paramaters
    ###############################################################
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true,Mandatory=$true)][string[]]$Servers
    )
    try{
        ###############################################################
        # Script Parameters
        ###############################################################
        Write-Output "========================="
        Write-Output "Deploy Cert Notification"
        Write-Output "========================="
        Write-Output "`r`nStart...`r`n"
        Write-Host "> Setting Script Paramaters " -NoNewline
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
        $destinationFolder = "D:\PowershellScripts\certNotification"
        $localFolder = "C:\temp\CertNotification"
        $awsEnvt = $env:aws_envt
        $triggerTask = 'Cert Expiry Trigger'
        $notificationTask = 'Notify Expired Cert'
        $s3KeyPrefix = "certNotification"
        $s3BucketName = $env:aws_envt + "-dbsql-rpl"
        Write-Host @pass

        ###############################################################
        # Download S3 Files
        ################################################################
        Write-Host "`r`n> Downloading Files from S3 " -NoNewline
        if (Test-Path $localFolder) {
            Remove-Item $localFolder -Recurse -Force
        }
        Read-S3Object -BucketName $s3BucketName -KeyPrefix $s3KeyPrefix -Folder $localFolder | Out-Null
        Write-Host @pass

        ###############################################################
         # Begin Server Deployment
        ###############################################################
        Write-Host "`r`n> Deploying...`r`n" 
        $Servers | % {
            $_ -Split "`r`n" | % {
                $stack = $($_.ToString().Trim().Split(','))[0]
                $vpc = $($_.ToString().Trim().Split(','))[1]
                $srv = $($_.ToString().Trim().Split(','))[2]
            }
            $destination = "\\$($srv)\$($destinationFolder.Replace(':','$'))"
            $exclude = @($MyInvocation.MyCommand.Name)
            Write-Host "Stack: $($stack)" -ForegroundColor Cyan
            Write-Host "VPC: $($vpc)" -ForegroundColor Cyan
            Write-Host "Server: $($srv)" -ForegroundColor Cyan

            ############################################################### 
            # DOMAINLESS
            ###############################################################
            if(!(Get-ADComputer -Filter {Name -eq $srv} -ErrorAction SilentlyContinue)){            
                $userAccount = 'sa_sqlbackup'
                $serverPWord =  ConvertTo-SecureString $(Get-AdminPassword -clusterName $stack -VPC $vpc -userAccount $userAccount) -AsPlainText -Force
                $serverCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userAccount, $serverPWord

                ############################################################### 
                ## Copy Files
                ###############################################################
                Write-Host "`r`n  - Copying Files " -NoNewline
                $mapDrive = "X"
                $mapLocation = "\\$($srv)\$($destinationFolder.Substring(0,2).Replace(':','$'))"
                $destination = $destinationFolder.Replace($destinationFolder.Substring(0,1), $mapDrive)
                New-PSDrive -Name $mapDrive -PSProvider FileSystem -Root $mapLocation -Credential $serverCredential | Out-Null
                New-Item $destination -Force -Type Directory | Out-Null
                Copy-Item "$($localFolder)\*" $destination -Exclude "$($exclude).ps1" -Recurse -Force -Confirm:$false | Out-Null
                Remove-PSDrive $mapDrive -Force | Out-Null
                Write-Host @pass

                ###############################################################
                # Connect To Server
                ###############################################################
                Write-Host "`r`n  - Connecting to Server " -NoNewline
                Invoke-Command -ComputerName $srv -Credential $serverCredential -ScriptBlock{
                    try{
                        Write-Host @using:pass

                        ###############################################################
                        # Remove Existing Tasks
                        ################################################################
                        Write-Host "`r`n  - Checking for Trigger Task '$($using:triggerTask)' " -NoNewline
                        $getTriggerTask  = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:triggerTask } -ErrorAction Stop
                        Write-Host @using:pass
                        if ($getTriggerTask){
                            Write-Host "`r`n  - Removing Trigger Task '$($using:triggerTask)' " -NoNewline
                            Unregister-ScheduledTask -TaskName $using:triggerTask -TaskPath $getTriggerTask.TaskPath -Confirm:$false -ErrorAction Stop
                            Write-Host @using:pass
                        }

                        Write-Host "`r`n  - Checking for Notification Task '$($using:notificationTask)' " -NoNewline
                        $getNotificationTask  = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:notificationTask } -ErrorAction Stop
                        Write-Host @using:pass
                        if ($getNotificationTask){
                            Write-Host "`r`n  - Removing Notification Task '$($using:notificationTask)' " -NoNewline
                            Unregister-ScheduledTask -TaskName $using:notificationTask -TaskPath $getNotificationTask.TaskPath -Confirm:$false -ErrorAction Stop
                            Write-Host @using:pass
                        }

                        ###############################################################
                        # Register New Tasks
                        ################################################################
                        Write-Host "`r`n  - Registering Trigger Task '$($using:triggerTask)' " -NoNewline
                        Register-ScheduledTask -Xml (Get-Content -Path "$using:destinationFolder\CertExpiryTrigger.xml" | Out-String).Replace('$vpc', $using:vpc).Replace('$stack', $using:stack) -TaskName $using:triggerTask -User "System" -ErrorAction Stop | Out-Null
                        Write-Host @using:pass

                        Write-Host "`r`n  - Registering Initial Notification Task '$($using:notificationTask)' " -NoNewline
                        $initialNotificationTask = "$using:destinationFolder\Create-InitialExpiredCertNotification.ps1"
                        . $initialNotificationTask -VPC $($using:vpc) -Stack $($using:stack) -ErrorAction Stop | Out-Null
                        Write-Host @using:pass

                        ###############################################################
                        # Validate
                        ###############################################################
                        Write-Host "`r`n`r`n Validating...."
                        Write-Host "`r`n  - Trigger Task '$($using:triggerTask)' created " -NoNewline
                        $getRegisteredTriggerTask = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:triggerTask } -ErrorAction Stop
                        if ($getRegisteredTriggerTask){
                            Write-Host @using:pass
                        } else{
                            Write-Host @using:fail
                        }

                        Write-Host "`r`n  - Notification Task '$($using:notificationTask)' created " -NoNewline
                        $getRegisteredNotificationTask = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:notificationTask } -ErrorAction Stop
                        if ($getRegisteredNotificationTask){
                            Write-Host @using:pass
                        } else{
                            Write-Host @using:fail
                        }
                        
                        Write-Host "`r`n  - SQL Thumbprint created " -NoNewline
                        $sqlQuery = "
                        IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE name = 'sqlCertThumbPrint')
                        SELECT 1 AS SQLThumbprint
                        "
                        try {
                            $sqlThumbprint = (Invoke-Sqlcmd -Database master -Query $sqlQuery -TrustServerCertificate).sqlThumbprint
                        }
                        catch {
                            $sqlThumbprint = (Invoke-Sqlcmd -Database master -Query $sqlQuery).sqlThumbprint
                        }
                        if ($sqlThumbprint -eq 1){
                            Write-Host @using:pass
                        } else{
                            Write-Host @using:fail
                        }
                                     
                        Write-Host "`r`n"
                    } catch{
                        Write-Host @using:fail
                        Write-Host "`r`n  $($_)`r`n" -ForegroundColor Red
                    }
                }
                                        
            ###############################################################
            # DOMAIN
            ###############################################################
            } else{
                ###############################################################
                #Copy Files
                ###############################################################
                Write-Host "`r`n  - Copying Files " -NoNewline
                New-Item $destination -Force -Type Directory | Out-Null
                Copy-Item "$($localFolder)\*" $destination -Exclude "$($exclude).ps1" -Recurse -Force -Confirm:$false | Out-Null
                Write-Host @pass

                ###############################################################
                # Connect To Server
                ###############################################################
                Write-Host "`r`n  - Connecting to Server " -NoNewline
                Invoke-Command -ComputerName $srv -Scriptblock{
                    try{
                        Write-Host @using:pass

                        ###############################################################
                        # Remove Existing Tasks
                        ################################################################
                        Write-Host "`r`n  - Checking for Trigger Task '$($using:triggerTask)' " -NoNewline
                        $getTriggerTask  = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:triggerTask } -ErrorAction Stop
                        Write-Host @using:pass

                        if ($getTriggerTask){
                            Write-Host "`r`n  - Removing Trigger Task '$($using:triggerTask)' " -NoNewline
                            Unregister-ScheduledTask -TaskName $using:triggerTask -TaskPath $getTriggerTask.TaskPath -Confirm:$false -ErrorAction Stop
                            Write-Host @using:pass
                        }

                        Write-Host "`r`n  - Checking for Notification Task '$($using:notificationTask)' " -NoNewline
                        $getNotificationTask  = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:notificationTask } -ErrorAction Stop
                        Write-Host @using:pass

                        if ($getNotificationTask) {
                            Write-Host "`r`n  - Removing Notification Task '$($using:notificationTask)' " -NoNewline
                            Unregister-ScheduledTask -TaskName $using:notificationTask -TaskPath $getNotificationTask.TaskPath -Confirm:$false -ErrorAction Stop
                            Write-Host @using:pass
                        }

                        ###############################################################
                        # Register New Tasks
                        ################################################################
                        Write-Host "`r`n  - Registering Trigger Task '$($using:triggerTask)' " -NoNewline
                        Register-ScheduledTask -Xml (Get-Content -Path "$using:destinationFolder\CertExpiryTrigger.xml" | Out-String).Replace('$vpc', $using:vpc).Replace('$stack', $using:stack) -TaskName $using:triggerTask -User "System" -ErrorAction Stop | Out-Null
                        Write-Host @using:pass

                        Write-Host "`r`n  - Registering initial Notification Task '$($using:notificationTask)' " -NoNewline
                        $initialNotificationTask = "$using:destinationFolder\Create-InitialExpiredCertNotification.ps1"
                        . $initialNotificationTask -VPC $($using:vpc) -Stack $($using:stack) -ErrorAction Stop | Out-Null
                        Write-Host @using:pass
                        
                        ###############################################################
                        # Validate
                        ###############################################################
                        Write-Host "`r`n`r`n  Validating...."
                        Write-Host "`r`n  - Trigger Task '$($using:triggerTask)' created " -NoNewline
                        $getRegisteredTriggerTask = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:triggerTask } -ErrorAction Stop
                        if ($getRegisteredTriggerTask){
                            Write-Host @using:pass
                        } else{
                            Write-Host @using:fail
                        }

                        Write-Host "`r`n  - Notification Task '$($using:notificationTask)' created " -NoNewline
                        $getRegisteredNotificationTask = Get-ScheduledTask | Where-Object {$_.TaskName -eq $using:notificationTask } -ErrorAction Stop
                        if ($getRegisteredNotificationTask){
                            Write-Host @using:pass
                        } else{
                            Write-Host @using:fail
                        }

                        Write-Host "`r`n  - SQL Thumbprint created " -NoNewline
                        $sqlQuery = "
                        IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE name = 'sqlCertThumbPrint')
                        SELECT 1 AS SQLThumbprint
                        "
                        try {
                            $sqlThumbprint = (Invoke-Sqlcmd -Database master -Query $sqlQuery -TrustServerCertificate).sqlThumbprint
                        }
                        catch {
                            $sqlThumbprint = (Invoke-Sqlcmd -Database master -Query $sqlQuery).sqlThumbprint
                        }
                        if ($sqlThumbprint -eq 1){
                            Write-Host @using:pass
                        } else{
                            Write-Host @using:fail
                        }
                  
                        Write-Host "`r`n"
                    } catch{
                       Write-Host @using:fail
                       Write-Host "`r`n  $($_)`r`n" -ForegroundColor Red
                    }
                } 
            }       
        }
    } catch{
          Write-Host @fail
          Write-Host "`r`n$($_)`r`n" -ForegroundColor Red         
    }
    ###############################################################  
    finally {
        Write-Host "End"
    }
    ###############################################################
} 