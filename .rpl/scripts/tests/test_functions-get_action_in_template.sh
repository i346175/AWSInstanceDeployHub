#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh


TMPL="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/templates/FIPS-WorkStation-Domain.json"
#TMPL="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/templates/MSSQLSG-MssqlFsx.yaml"

get_action_in_template $TMPL
search_action_in_template "S3Bucket" $TMPL