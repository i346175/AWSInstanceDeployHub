#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh


REPOPATH="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
TMPL="templates/LicenseManager/MSSQLDH-LicenseManager.yaml"
Account="integration-imaging"


search_account_in_template $Account $TMPL $REPOPATH
get_action_in_template