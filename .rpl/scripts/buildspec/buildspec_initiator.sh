#!/usr/bin/env bash
. .rpl/scripts/functions.sh
set -x
declare -r CODEBUILD_INITIATOR="$1"
declare -r PHASE="$2"


if [[ $PHASE == "install" ]]; then
  declare REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
  store_variables "REPO_NAME" ${REPO_NAME}
  store_variables "CODEBUILD_SRC_DIR" ${CODEBUILD_SRC_DIR}
  store_variables "CODEBUILD_BUILD_NUMBER" ${CODEBUILD_BUILD_NUMBER}

  STATUS=false

  #return value behind "rule/" from $CODEBUILD_INITIATOR if rule exists in variable
  #test if rule exists in variable
  if [[ $CODEBUILD_INITIATOR == "rule/"* ]]; then
    #get the value behind "rule/" to get schedule name
    declare -r SCHEDULE_NAME=$(echo $CODEBUILD_INITIATOR | cut -d'/' -f 2)
    SCHEDULE_TYPE=$(get_schedule_type_config_value "$SCHEDULE_NAME" "$CODEBUILD_SRC_DIR")
    
    store_variables "INITIATOR" "$SCHEDULE_NAME"
    store_variables "SCHEDULE_TYPE" "$SCHEDULE_TYPE"
    
    if [[ "$SCHEDULE_TYPE" == "dbsqlAMIIntTest" ]]; then
      store_variables "ACTION" "ScheduleDeployTest"
    else
      store_variables "ACTION" "ScheduleDeploy"
    fi

  else
    log "No eventbridge rule found"
    
    SCHEDULE_TYPE=""
    INITIATOR="MANUAL"
    store_variables "SCHEDULE_TYPE" ""
    store_variables "INITIATOR" "MANUAL"
    store_variables "ACTION" "Deploy"
  fi

  if [[ "$SCHEDULE_TYPE" == "buildAMI" ]] ; then
    nohup /usr/local/bin/dockerd --host=unix:///var/run/docker.sock --host=tcp://127.0.0.1:2375 --storage-driver=overlay2 &
    timeout 15 sh -c "until docker info; do echo .; sleep 1; done"
  elif [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL"  ]]; then
    docker pull quay.cnqr.delivery/ktg/supply-chain:main
    #set the yq_linux_amd64 yq parser from .rpl/files/yq_linux_amd64 to /usr/bin/yq path and set execution permission
    cp "$CODEBUILD_SRC_DIR"/.rpl/files/yq_linux_amd64 /usr/bin/yq
    #curl -vv -k https://artifactory.concurtech.net/artifactory/util-release-local/RplRepoDraft/yq_linux_amd64 -o /usr/bin/yq && chmod +x /usr/bin/yq
    chmod +x /usr/bin/yq
    #get yq version
    /usr/bin/yq --version
  else
    log "Nothing to run in phase install"
    exit 1
  fi

elif [[ $PHASE == "pre_build" ]]; then
  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out)

  if [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL" ]]; then

    .rpl/scripts/buildspec/buildspec_prebuild.sh
  else

    log "Nothing to run in phase pre-build"
    exit 1
  fi


elif [[ $PHASE == "build" ]]; then
  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out)

  if [[ "$SCHEDULE_TYPE" == "buildAMI" ]] ; then
    
    if [[ "$SCHEDULE_NAME" == "dbsqlAMIIntBuild" ]] ; then
      .rpl/ami/build-ami.sh .rpl/files/windows-generic/properties.json
    elif [[ "$SCHEDULE_NAME" == "solwAMIIntBuild" ]] ; then
      .rpl/ami/build-ami.sh .rpl/files/linux-generic/properties.json
    fi

  elif [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL" ]] ; then
    .rpl/scripts/buildspec/buildspec_build.sh ${CODEBUILD_BUILD_NUMBER} ${CODEBUILD_SOURCE_REPO_URL}
  fi

elif [[ $PHASE == "post_build" ]]; then
  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out)
    
    ORG=$(get_config_value "ORG" "$CODEBUILD_SRC_DIR")
    ROLE_TYPE=$(get_config_value "ROLE_TYPE" "$CODEBUILD_SRC_DIR")
    PROMOTIONS_BUCKET=$(get_config_value "PROMOTIONS_BUCKET" "$CODEBUILD_SRC_DIR")
    REPO_NAME=$(<REPO_NAME.out)

    if [[ "$SCHEDULE_TYPE" == "buildAMI" || $SCHEDULE_TYPE == "promoteAMI" ]] ; then
        AMI_PROMOTION_TARGETS=$(jq -c . .rpl/ami/ami_promotion_targets.json)
        AMI_ID=$(cat ami-id.txt)

        env > env.vars
        docker run --env-file env.vars \
          quay.cnqr.delivery/ktg/supply-chain:main promote ami \
          --ami-id ${AMI_ID} \
          --roletype ${ROLE_TYPE} \
          --source-commit ${CODEBUILD_RESOLVED_SOURCE_VERSION} \
          --source-repo ${ORG}/${REPO_NAME} \
          --targets ${AMI_PROMOTION_TARGETS}
    elif [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL" ]]; then
      declare BRANCH_NAME=$(<BRANCH_NAME.out)
      .rpl/scripts/buildspec/buildspec_postbuild.sh ${PROMOTIONS_BUCKET} ${ORG} ${REPO_NAME} ${CODEBUILD_RESOLVED_SOURCE_VERSION} ${ROLE_TYPE} ${BRANCH_NAME}
    fi

elif [[ $PHASE == "finally" ]]; then
  STATUS=true
  .rpl/scripts/buildspec/buildspec_finally.sh "${STATUS}"
fi
