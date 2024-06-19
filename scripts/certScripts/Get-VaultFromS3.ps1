$env:https_proxy = ''
New-Item -ItemType Directory -Path C:\vault -Force | out-null
$s3bucket=$aws:envt + "-dbsql-rpl"
aws s3 cp  s3://$s3bucket/AWSInstanceDeployHub/scripts/vault/ C:\vault\ --recursive --no-progress
