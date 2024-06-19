#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

custom_parameter_value_file="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/templates/MSSQLEC2-DBAWKS.config"
KEY="04"

assign_values_to_custom_parameters "$custom_parameter_value_file" "$KEY" $ENV



