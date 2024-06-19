#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions_aws.sh
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

CHANGED_TMPL=".rpl/scripts/CHANGED_TMPL.out"
CHANGED_TMPL_WITH_PKG=".rpl/scripts/CHANGED_TMPL_WITH_PKG.out"
account="integration-tools"
REPOPATH="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"

get_templates_for_deploy_in_account "${account}" "${CHANGED_TMPL_WITH_PKG}" "${CHANGED_TMPL}" "${REPOPATH}"


