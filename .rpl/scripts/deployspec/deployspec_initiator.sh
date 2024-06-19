#!/usr/bin/env bash
. .rpl/scripts/functions.sh
set -x
declare -r PHASE="$1"


if [[ $PHASE == "install" ]]; then

  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out)

  #clean file
  echo "" > CODEBUILD_SRC_DIR.out
  #set new cotainer path
  store_variables "CODEBUILD_SRC_DIR" ${CODEBUILD_SRC_DIR}


   if [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL"  ]]; then
      export CA_BUNDLE_BOOTSTRAPPER="ca.service.cnqr.tech"
      curl -skS "https://${CA_BUNDLE_BOOTSTRAPPER}/v1/trust/bundle.crt" > /etc/pki/ca-trust/source/anchors/root.crt
      update-ca-trust extract
      echo "Installing yq...."
      cp "$CODEBUILD_SRC_DIR"/.rpl/files/yq_linux_amd64 /usr/bin/yq
      #curl -vv -k --proxy 'http://proxy.service.cnqr.tech:3128' https://artifactory.concurtech.net/artifactory/util-release-local/RplRepoDraft/yq_linux_amd64 -o /usr/bin/yq && chmod +x /usr/bin/yq
      chmod +x /usr/bin/yq
      #get yq version
      /usr/bin/yq --version   
      log "Phase install completed successfully"
      exit 0
   else
      log "Nothing to run in phase install"
      exit 1
   fi

elif [[ $PHASE == "pre_build" ]]; then
  
  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out)

  if [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL" ]]; then
   
    export AWS_STS_REGIONAL_ENDPOINTS=regional
    chmod -R u+x .rpl/scripts/*
    env
    .rpl/scripts/deployspec/deployspec_prebuild.sh "${RPL_MULTI_TARGET_ACCOUNTS_IDS}" ${RPL_AWS_PARTITION}
    if [ $? -eq 0 ]
    then
      log "Phase pre-build completed successfully"
      exit 0
    else
      log "Phase pre-build failed"    
      exit 1
    fi
  else
      log "Nothing to run in phase pre-build"
      exit 1
  fi

elif [[ $PHASE == "build" ]]; then

  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out)

  if [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL" ]] ; then
      .rpl/scripts/deployspec/deployspec_build.sh ${RPL_AWS_PARTITION}
      if [ $? -eq 0 ]
      then
        log "Phase build completed successfully"
        exit 0
      else
        log "Phase build failed"    
        exit 1
      fi
  fi

elif [[ $PHASE == "post_build" ]]; then   
  declare INITIATOR=$(<INITIATOR.out)
  declare SCHEDULE_TYPE=$(<SCHEDULE_TYPE.out) 

  if [[ "$SCHEDULE_TYPE" == "buildTemplate" || "$INITIATOR" == "MANUAL" ]]; then
    .rpl/scripts/deployspec/deployspec_postbuild.sh
    if [ $? -eq 0 ]
    then
      log "Phase postbuild completed successfully"
      exit 0
    else
      log "Phase postbuild failed"    
      exit 1
    fi
  fi
elif [[ $PHASE == "finally" ]]; then
  .rpl/scripts/deployspec/deployspec_finally.sh
  if [ $? -eq 0 ]
  then
    log "Phase finally completed successfully"
    exit 0
  else
    log "Phase finally failed"    
    exit 1
  fi
fi
