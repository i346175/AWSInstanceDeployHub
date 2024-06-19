#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

CODEBUILD_SRC_DIR="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
tmpl_path="templates/MSSQLLambda-SendNotification/MSSQLLambda-SendNotification.yaml"


get_custom_parameter_value_file  "$tmpl_path" "$CODEBUILD_SRC_DIR"

