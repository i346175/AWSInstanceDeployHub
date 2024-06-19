#Requires -RunAsAdministrator

function Deploy-CFNCertNotification{
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
        Write-Output ""
        Write-Output "BEGIN"
        Write-Output "Deploy Cert Notification"
        Write-Output "> Setting Script Paramaters"
        $destinationFolder = "D:\PowershellScripts\certNotification"
        $triggerTask = 'Cert Expiry Trigger'
        $notificationTask = 'Notify Expired Cert'
        ###############################################################
         # Begin Server Deployment
        ###############################################################
        Write-Output "> Deploying..." 
        $Servers | % {
            $_ -Split "`r`n" | % {
                $stack = $($_.ToString().Trim().Split(','))[0]
                $vpc = $($_.ToString().Trim().Split(','))[1]
            }
            ###############################################################
            # Register New Tasks
            ################################################################
            Write-Output "- Registering Trigger Task '$($triggerTask)'" 
            Register-ScheduledTask -Xml (Get-Content -Path "$destinationFolder\CertExpiryTrigger.xml" | Out-String).Replace('$vpc', $vpc).Replace('$stack', $stack) -TaskName $triggerTask -User "System" -ErrorAction Stop | Out-Null

            Write-Output "- Registering Initial Notification Task '$($notificationTask)'" 
            $initialNotificationTask = "$destinationFolder\Create-InitialExpiredCertNotification.ps1"
            . $initialNotificationTask -VPC $($vpc) -Stack $($stack) -ErrorAction Stop | Out-Null    
        }
    } catch{
          Write-Output "$($_)"       
    }
    ###############################################################  
    finally {
        Write-Output "END"
    }
    ###############################################################
} 