#!/usr/bin/env bash
set -x
. .rpl/scripts/functions.sh


declare -r PROMOTIONS_BUCKET="$1"
declare -r ORG="$2"
declare -r REPO="$3"
declare -r CODEBUILD_RESOLVED_SOURCE_VERSION="$4"
declare -r ROLETYPE="$5"
declare -r BRANCH_NAME="$6"

declare CODEBUILD_BUILD_NUMBER=$(<CODEBUILD_BUILD_NUMBER.out)
declare TARGET_ENVS=$(<TARGET_ENVS.out)

log "##################### post_build STARTED #####################"

if ! test -z "$TARGET_ENVS" ; then
    ZIP_FILENAME=${BRANCH_NAME}-${CODEBUILD_BUILD_NUMBER}-deployment.zip
    zip -r ${ZIP_FILENAME} -r . 
fi

# Upload your deployment.zip to the build S3 bucket
if ! test -z "$TARGET_ENVS" ; then
    ZIP_UPLOAD_PATH="${PROMOTIONS_BUCKET}/${ORG}/${REPO}/${ZIP_FILENAME}"
    aws s3 cp ${ZIP_FILENAME} s3://${ZIP_UPLOAD_PATH}
fi

# Promote your zip file with supply-chain CLI to initiate the deployment
if ! test -z "$TARGET_ENVS" ; then
    env > env.vars
    echo "Promoting artifacts to ${TARGET_ENVS}"
    docker run --env-file env.vars \
    quay.cnqr.delivery/ktg/supply-chain:main promote zipfile \
    --zip-location "arn:aws:s3:::${ZIP_UPLOAD_PATH}" \
    --target-environments "${TARGET_ENVS}" \
    --source-repo="${ORG}/${REPO}" \
    --source-commit="${CODEBUILD_RESOLVED_SOURCE_VERSION}" \
    --roletype "${ROLETYPE}" \
    --wait=true \
    --blocking-exception 'CSCI-6769'
fi


log "##################### post_build FINISHED #####################"
