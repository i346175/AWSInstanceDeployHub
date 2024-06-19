#!/usr/bin/env bash

. .rpl/scripts/functions.sh

declare -r STATUS="$1"
declare BRANCH_NAME=$(<BRANCH_NAME.out)
declare CODEBUILD_BUILD_NUMBER=$(<CODEBUILD_BUILD_NUMBER.out)
declare TARGET_ENVS=$(<TARGET_ENVS.out)
declare REPO_NAME=$(<REPO_NAME.out)

declare message="Environment: ${TARGET_ENVS}, Build Number: ${CODEBUILD_BUILD_NUMBER}, Branch Name: ${BRANCH_NAME}"


log "##################### finally STARTED #####################"

case $STATUS in 
"true")
    slack_notify "${REPO_NAME} - Build SUCCESS" "good" "${message}"
    log "Build SUCCESS! Sending output to slack chanel."
    ;;
"false")
    slack_notify "${REPO_NAME} - Build FAILED" "danger" "${message}"
    log "build FAILED! Sending output to slack chanel." "error"
    ;;
esac

log "##################### finally FINISHED #####################"