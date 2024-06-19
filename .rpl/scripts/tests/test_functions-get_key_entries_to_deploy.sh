#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

file="templates/MSSQLEC2-DBAWKS.config"
REPO_PATH="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
ENV="integration"

get_key_entries_for_action_account "$file" $REPO_PATH "ScheduleDeploy" "integration-tools" $ENV


