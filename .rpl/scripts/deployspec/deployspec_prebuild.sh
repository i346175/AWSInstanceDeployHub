#!/usr/bin/env bash

. .rpl/scripts/functions.sh
. .rpl/scripts/functions_aws.sh

declare -r RPL_MULTI_TARGET_ACCOUNTS_IDS="$1"
declare -r RPL_AWS_PARTITION="$2"

set -x
declare CODEBUILD_BUILD_NUMBER=$(<CODEBUILD_BUILD_NUMBER.out)
declare REPO_NAME=$(<REPO_NAME.out)
declare ENVIRONMENT=$(<ENVIRONMENT.out)
declare TEMPLATES_FOLDER=$(<TEMPLATES_FOLDER.out)
declare TEMPLATESZIP="$(<TEMPLATESZIP.out)"
declare TEMPLATES_TO_S3BUCKET="TEMPLATES_TO_S3BUCKET.out"
declare CHANGED_FILES="CHANGED_FILES.out"
declare CHANGED_SCRIPTS="CHANGED_SCRIPTS.out"
declare TEMPLATES_MASTER="$TEMPLATES_MASTER.out"
declare S3_TEMPLATE_PATH=$REPO_NAME/$TEMPLATES_FOLDER

log "##################### pre-build STARTED #####################"
log "Create buckets, copy templates and zipped packaged to this bucket"

#ITERATE PER ACCOUNT
IFS=' ' read -a multiAccounts <<< "${RPL_MULTI_TARGET_ACCOUNTS_IDS}" #Create an array of account IDs
for acc in "${multiAccounts[@]}"
do
    #Return environment-account , ex. integration-tools
    account=$(get_account_info "$acc" "$CODEBUILD_SRC_DIR")
    #Return environment, ex. integration
    ENV=$(get_environment "$acc" "$CODEBUILD_SRC_DIR")
    region=$(get_environment_values $ENV $CODEBUILD_SRC_DIR "region")
    default_account=$(get_environment_values $ENV $CODEBUILD_SRC_DIR "default_account")

    #Implement environmently dependend resources via default_account
    if [[ "$account" == "$default_account" ]]; then
        
        #Get bucket name from config
        bucket_name=$(get_environment_values $ENV $CODEBUILD_SRC_DIR "bucket_name")
    
        log "Account is ${account}, assuming the deployer role in default_account "

        assume_role "$acc" "$REPO_NAME" "$RPL_AWS_PARTITION" "$region"

        #If bucket_name is empty in config file so use standard one for one regions
        if [[ "$bucket_name" == "" ]]; then
            bucket_name="$ENV"-dbsql-rpl
        fi
        
        #Check if bucket_name exist in S3 if not create it from defined template
        if ( aws s3api head-bucket --bucket "$bucket_name" 2>&1 | grep -q 'Not Found' ); then 
            #Deploy bucket from template
            log "Creating new BUCKET ${bucket_name}"

            aws cloudformation deploy \
            --template-file ".rpl/CFN/MSSQLS3-dbsql-rpl.yaml" \
            --stack-name "${bucket_name}" \
            --region "$region" \
            --capabilities 'CAPABILITY_NAMED_IAM' 'CAPABILITY_AUTO_EXPAND' \
            --parameter-overrides "Name=${bucket_name}"
            retcode=$?
            if [[ ${retcode} -ne 0 ]]; then
                log "Failed to deploy bucket ${bucket_name} in ${account} and region ${region}" "error"
                add_final_results "${account} (${region}) ${bucket_name} deploy failed" "failed"
                send_final_result "${CODEBUILD_BUILD_NUMBER}" "${ENVIRONMENT}" "${REPO_NAME}"                
                exit 1
            else
                bucket_created="true"
            fi
            #wait until the bucket is created
            aws s3api wait bucket-exists --bucket "$bucket_name"
            #send notification to slack
            slack_notify "${REPO_NAME}" "info" "Bucket ${bucket_name} created"
        else
                #aws cloudformation update-stack if bucket already exist
                log "Updating BUCKET ${bucket_name} in ${account} and region ${region}"
                update_output=$(aws cloudformation update-stack \
                    --template-body file://.rpl/CFN/MSSQLS3-dbsql-rpl.yaml \
                    --stack-name "${bucket_name}" \
                    --region "$region" \
                    --capabilities 'CAPABILITY_NAMED_IAM' 'CAPABILITY_AUTO_EXPAND' \
                    --parameters "ParameterKey='Name',UsePreviousValue=true" \
                    2>&1)
                retcode=$?
                if [[ $retcode -ne 0 && ! "$update_output" =~ "No updates are to be performed" ]]; then
                    log "Failed to update bucket ${bucket_name} in ${account} and region ${region}" "skipped"
                    add_final_results "${account} (${region}) ${bucket_name} update failed" "skipped"
                    send_final_result "${CODEBUILD_BUILD_NUMBER}" "${ENVIRONMENT}" "${REPO_NAME}"
                    bucket_created="false"
                elif [[ $retcode -eq 0 ]]; then

                    slack_notify "${REPO_NAME}" "info" "Bucket ${bucket_name} updated"
                    bucket_created="false"
                fi
        fi

        #Copy AMI to S3 Bucket if specified ".rpl/ami/s3"
        copy_ami_S3Bucket "$bucket_name" "$REPO_NAME" "$CODEBUILD_SRC_DIR"

        #Copy changed files in SCRIPTs folder to S3 Bucket
        copy_scripts_S3Bucket "$bucket_name" "$CHANGED_SCRIPTS" "$REPO_NAME" "$CODEBUILD_SRC_DIR" "$bucket_created" &

        #Check if there are templates with packages to copy packages with additional code to S3 Bucket
        #test if folder path "$CODEBUILD_SRC_DIR/$TEMPLATESZIP" exist and contain zip files
        if [[ -d "$CODEBUILD_SRC_DIR/$TEMPLATESZIP" ]] && [[ $(ls -1 "$CODEBUILD_SRC_DIR/$TEMPLATESZIP"/*.zip 2>/dev/null | wc -l) -ge 1 ]]; then
            log "There are templates with packages to deploy in ${account}..."
            log "Copying packages to s3://$bucket_name/$S3_TEMPLATE_PATH in ${account}..."
            for package in "$CODEBUILD_SRC_DIR/$TEMPLATESZIP"/*; 
            do
                copy_zippackage_S3 "$bucket_name" "$S3_TEMPLATE_PATH" "$package" &  
            done
            # Wait for all templates to update
            wait
            log "Copying packages FINISHED."
        else
            log "There is not additional code to copy to S3 Bucket in $ENV environment"
        fi

        #Check if there are some templates which won't be directly deployd so they have to be firstly copied to S3 Bucket
        if [[ $(stat -c %s "${TEMPLATES_TO_S3BUCKET}") -ge 2 ]]; then
            log "There are templates to copy to S3 Bucket in ${account}, ${region}..."
            log "Copying templates to BUCKET $bucket_name in ${account}, ${region}..."
            while read -r tmpl_path  ; do
                copy_templates_S3Bucket "$bucket_name" "$tmpl_path" "$REPO_NAME" &
            done <  "${TEMPLATES_TO_S3BUCKET}"
            # Wait for all templates to update
            wait
            log "Copying templates to S3 bucket FINISHED."
        else
            log "There are no templates to copy to S3 Bucket in $ENV environment..."
        fi
    fi

done


store_variables "RPL_MULTI_TARGET_ACCOUNTS_IDS" "${RPL_MULTI_TARGET_ACCOUNTS_IDS}"
store_variables "BUCKET_NAME" "${bucket_name}"

log "##################### pre_build FINISHED #####################"
exit 0