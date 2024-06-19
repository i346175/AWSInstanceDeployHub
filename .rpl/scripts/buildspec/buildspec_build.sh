#!/usr/bin/env bash

. .rpl/scripts/functions.sh
. .rpl/scripts/functions_aws.sh

set -x

declare -r CODEBUILD_BUILD_NUMBER="$1"
declare -r CODEBUILD_SOURCE_REPO_URL="$2"


declare CODEBUILD_SRC_DIR=$(<CODEBUILD_SRC_DIR.out)
declare CODEBUILD_BUILD_NUMBER=$(<CODEBUILD_BUILD_NUMBER.out)
declare TEMPLATESZIP=$(<TEMPLATESZIP.out)
declare TEMPLATES_FOLDER=$(<TEMPLATES_FOLDER.out)
declare SCRIPTS_FOLDER=$(<SCRIPTS_FOLDER.out)
declare TARGET_ENVS=$(<TARGET_ENVS.out)
declare REPO_NAME=$(<REPO_NAME.out)
declare ACTION=$(<ACTION.out)


store_variables "CODEBUILD_SOURCE_REPO_URL" ${CODEBUILD_SOURCE_REPO_URL}


log "##################### build STARTED #####################"
log "Executing build steps in environment - ${TARGET_ENVS}"
log "Checking changed files"
ls -latr



# Calls the 'scan_templates' function to scan templates in the 
# specified TEMPLATES_FOLDER and store output about templates to deploy
# or upload to S3
# 
# Parameters:
# - TEMPLATES_FOLDER: The folder containing the templates to scan.  
# - CODEBUILD_SRC_DIR: The source directory for the CodeBuild project.
# - REPO_NAME: The name of the repository.  
# - TEMPLATESZIP: The name of the templates zip file.
# - CODEBUILD_BUILD_NUMBER: The build number of the CodeBuild project.  
# - ACTION: Deploy or ScheduleDeploy, ScheduleDeployTest or S3Bucket.
# - ENV: The environment to deploy to.
# Returns: TEMPLATES_TO_S3BUCKET.out and DEPLOY_TMPL.out files

scan_templates "$TEMPLATES_FOLDER" "$CODEBUILD_SRC_DIR" "$REPO_NAME" "$TEMPLATESZIP" "$CODEBUILD_BUILD_NUMBER" "$ACTION"
scan_scripts "$SCRIPTS_FOLDER" "$CODEBUILD_SRC_DIR" "$REPO_NAME"


#check if there templates for deploy or for storing to S3 Bucket
#if not exit
if [[ $(stat -c %s "DEPLOY_TMPL.out") -le 1 && $(stat -c %s "TEMPLATES_TO_S3BUCKET.out") -le 1 ]]; then
      # Sends Slack notification
    slack_notify "${REPO_NAME}" "warning" "Nothing to Deploy or upload to S3 Bucket - Exiting the cycle"
    exit 1
else
    log "Found templates for deploy or for storing to S3 Bucket"
fi
log "##################### build FINISHED #####################"
