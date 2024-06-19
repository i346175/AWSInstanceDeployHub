#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

CHANGED_TMPL="templates/LicenseManager/MSSQLRAM-ResourceShare.yml"
REPOPATH="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
get_parameters_from_template "$CHANGED_TMPL" $REPOPATH

