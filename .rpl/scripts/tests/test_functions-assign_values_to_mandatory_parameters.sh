#!/usr/bin/env bash
#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh

CODE_BUILD_NUMBER=300
account="integration-tools"
BUCKET_NAME="integration-dbsql-shared"
S3_TEMPLATE_PATH="pathtotemplate"
tmpl_path="templates/LicenseManager/MSSQLRAM-ResourceShare.yml"
REPO_PATH="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
use_pckg=false


assign_values_to_mandatory_parameters "$account" "$BUCKET_NAME" "$S3_TEMPLATE_PATH" "$tmpl_path" "$CODE_BUILD_NUMBER" "$use_pckg" "$REPO_PATH"

