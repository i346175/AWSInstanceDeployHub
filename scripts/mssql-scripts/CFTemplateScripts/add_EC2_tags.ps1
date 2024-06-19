param(
    [parameter(Mandatory=$true)][string]$awsStackName,
    [parameter(Mandatory=$true)][string]$VPC,
    [parameter(Mandatory=$true)][string]$PrimaryCName,
    [parameter(Mandatory=$true)][string]$AdditionalCNames,
    [parameter(Mandatory=$true)][string]$SQLVersion
)
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
        Write-Output $logstring | Out-File -Append "C:\mssql-scripts\automation_logs\add_EC2_tags.log"
}

try {
    $instance = Invoke-WebRequest http://169.254.169.254/latest/dynamic/instance-identity/document -UseBasicParsing | ConvertFrom-Json
    $inst_id = $instance.instanceId
    $key = "HostName"
    $value = $env:COMPUTERNAME
    $microservicekey = "MicroService"
    $microservicevalue = switch -wildcard ($awsStackName){
        "Tools*" {"tools"; break} 
        "Test*" {"test"; break} 
        "OuttaskSN*" {"outtasksession"; break} 
        "OuttaskSQ*" {"outtask"; break} 
        "Itin*" {"itinerary"; break} 
        "TravelMisc*" {"travel-misc"; break} 
        "CTHost*" {"cthost"; break} 
        "SpendExp*" {"expense"; break} 
        "SpendImpl*" {"spend-impl"; break} 
        "SpendMisc*" {"spend-misc"; break} 
        "ConcurPay*" {"concurpay"; break} 
        "Reporting*" {"reporting"; break} 
        "CognosDB*" {"cognos"; break} 
        "Imaging*" {"imaging"; break}
    }
    
    $defaultSuffice = "$($VPC).cnqr.tech"
    $CNamesKey = "CNameList"
    $SQLVersionKey="SQLVersion"
    
    #Condition added as part of CSCI-6056
    If($PrimaryCName.ToLower() -notlike "*dummy*"){
        $CNamesValue = "$($PrimaryCName.Split('.')[0]).$defaultSuffice"
    }
    Else{ $CNamesValue = '' }
    
    If($AdditionalCNames -ne 'none'){
        $addCNameList = ''
        $AdditionalCNames.Split(',') | ForEach-Object{
            $cn = $_.Trim()
            $addCNameList += ",$cn"
        }
        $CNamesValue += "$addCNameList"
    }
    $CNamesValue = $CNamesValue.ToLower().Trim(',')

    [System.Environment]::SetEnvironmentVariable('microservice',$microservicevalue,[System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('cnamelist',$CNamesValue,[System.EnvironmentVariableTarget]::Machine)

    aws ec2 create-tags --resources $inst_id --tags "Key=$key,Value=$value" "Key=$microservicekey,Value=$microservicevalue" "Key=$CNamesKey,Value=`'$CNamesValue`'" "Key=$SQLVersionKey,Value=$SQLVersion"
    log "Added EC2 tags: HostName, MicroService and CNameList"
    } 
catch {
    log "Failed to add EC2 tags"
    $_ | Format-List -Force
}
