#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

ACCOUNT="integration-front"
REPOPATH="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
name="MSSQLIAM-MSSQLOpsRole"


get_stack_name_in_account "$ACCOUNT" "$REPOPATH" "$name"
#test that there is return the value one
status=$?
if [ $status -ne 0 ]; then  
    stack_name="${manual_stack_name}" 
    echo "MANUAL"
#Stack is not multi stack and it does not have any custom parameter so stack name is same as template name
elif [[ $key == '' ]]; then
    stack_name="${name}"
    echo "AUTO"
else
    #Stack is multi stack and it has custom parameter so stack name is template name + key
    stack_name="${name}-${key}"
    echo "AUTO"
fi