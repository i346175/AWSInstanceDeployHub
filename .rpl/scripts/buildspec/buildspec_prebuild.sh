#!/usr/bin/env bash

. .rpl/scripts/functions.sh
set -x
#test if WEBHOOK variables exist if not set to empty
if [[ -z ${CODEBUILD_WEBHOOK_EVENT} ]]; then
  CODEBUILD_WEBHOOK_EVENT=""
fi
if [[ -z ${CODEBUILD_WEBHOOK_HEAD_REF} ]]; then
  CODEBUILD_WEBHOOK_HEAD_REF=""
fi
if [[ -z ${CODEBUILD_WEBHOOK_BASE_REF} ]]; then
  CODEBUILD_WEBHOOK_BASE_REF=""
fi
if [[ -z ${CODEBUILD_RESOLVED_SOURCE_VERSION} ]]; then
  CODEBUILD_RESOLVED_SOURCE_VERSION=""
fi
if [[ -z ${CODEBUILD_WEBHOOK_PREV_COMMIT} ]]; then
  CODEBUILD_WEBHOOK_PREV_COMMIT=""

fi


store_variables "DATE_OF_BUILD" ${DATE_OF_BUILD}
store_variables "CODEBUILD_SOURCE_REPO_URL" ${CODEBUILD_SOURCE_REPO_URL}


#GET CONFIG VALUES

TEMPLATES_FOLDER=$(get_config_value "TEMPLATES_FOLDER" "$CODEBUILD_SRC_DIR")
store_variables "TEMPLATES_FOLDER" "${TEMPLATES_FOLDER}"

SCRIPTS_FOLDER=$(get_config_value "SCRIPTS_FOLDER" "$CODEBUILD_SRC_DIR")
store_variables "SCRIPTS_FOLDER" "${SCRIPTS_FOLDER}"

TEMPLATESZIP="TemplatesZip"
store_variables "TEMPLATESZIP" "${TEMPLATESZIP}"
###########


log "##################### pre_build STARTED #####################"

if [[ "${CODEBUILD_WEBHOOK_EVENT}" == "PULL_REQUEST_MERGED" ]]; then
     #get what is the branch name of the PR the code is merged to
    BRANCH_NAME=$(echo $CODEBUILD_WEBHOOK_BASE_REF | sed -e 's,refs/heads/,,g')
    #get what is the branch name of the PR the code is merged from
    BRANCH_NAME_HEAD=$(echo $CODEBUILD_WEBHOOK_HEAD_REF | sed -e 's,refs/heads/,,g')

    #check if the BRANCH_NAME_HEAD is the 'main' or 'master' and finish deploy in this case
    #as it is not allowed to deploy from master or main
    if [[ "${BRANCH_NAME_HEAD}" == "main" || "${BRANCH_NAME_HEAD}" == "master" ]]; then
        log "Source branch name is ${BRANCH_NAME_HEAD} and it is not allowed to be deployed"
        slack_notify "${REPO_NAME}" "warning" "Nothing to Build/Deploy - Exiting the cycle"
        exit 1
    fi


    store_variables "BRANCH_NAME" ${BRANCH_NAME}
    log "Branch name is ${BRANCH_NAME}"

    # This function gets the branch information.
    #SET TARGET_ENVS and ENVIRONMENT according BRANCH_NAME (define in config.json)
    set_branch_info "$BRANCH_NAME" "$CODEBUILD_SRC_DIR"

    # Checkout the branch specified in the environment variable BRANCH_NAME
    git checkout ${BRANCH_NAME}

    # Get the list of files changed between the current and previous commit
    git diff --name-only HEAD^ HEAD

    # Store the list of changed files in the CHANGED_FILES variable
    CHANGED_FILES=$(git diff --name-only HEAD^ HEAD)

    # Log the list of changed files
    log "$CHANGED_FILES"

    # Store the CHANGED_FILES variable in the environment variables store
    store_variables "CHANGED_FILES" "${CHANGED_FILES}"

elif [[ "${CODEBUILD_WEBHOOK_EVENT}" == "" ]] ; then 

  store_variables "BRANCH_NAME" ${CODEBUILD_SOURCE_VERSION}
  BRANCH_NAME=$(<BRANCH_NAME.out)
  set_branch_info "$BRANCH_NAME" "$CODEBUILD_SRC_DIR"

else

    # This script sets the branch name, target environments, and changed files for the build process.
    # It stores these variables for later use in the build process.

    BRANCH_NAME=$(echo $CODEBUILD_WEBHOOK_HEAD_REF | sed -e 's,refs/heads/,,g')
    store_variables "BRANCH_NAME" ${BRANCH_NAME}

    set_branch_info "$BRANCH_NAME" "$CODEBUILD_SRC_DIR"

    git checkout ${BRANCH_NAME}
    git diff --name-only $CODEBUILD_RESOLVED_SOURCE_VERSION $CODEBUILD_WEBHOOK_PREV_COMMIT
    CHANGED_FILES=$(git diff --name-only $CODEBUILD_RESOLVED_SOURCE_VERSION $CODEBUILD_WEBHOOK_PREV_COMMIT)

    # Logs the changed files for debugging purposes.
    log "$CHANGED_FILES"

    store_variables "CHANGED_FILES" "${CHANGED_FILES}"
fi

git branch -a

##########################################################################################
# PRE CHECKS

if [[ "${CODEBUILD_WEBHOOK_EVENT}" != "" ]]; then

  # Checks if folder with templates is mentioned in changed files
  if ! grep -wq -e "$TEMPLATES_FOLDER" -e "$SCRIPTS_FOLDER" "CHANGED_FILES.out" ; then
    
    # Logs that nothing needs to be deployed
    log "Nothing to deploy." 
    
    # Sends Slack notification
    slack_notify "${REPO_NAME}" "warning" "Nothing to Build/Deploy - Exiting the cycle"
    
    # Exits with error
    exit 1 
  fi
fi

##########################################################################################



log "##################### pre_build FINISHED #####################"
