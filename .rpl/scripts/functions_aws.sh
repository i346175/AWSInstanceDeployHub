#!/usr/bin/env bash
# This is a shell file containing additional functions for deployment/build of all AWS objects in this repository
. .rpl/scripts/functions.sh

##################################################################################################
#Templates DEPLOYMENT

# Function that uploads the templates to S3
# Params:
# - BUCKET_NAME: Name of AWS S3 bucket.
# - S3_TEMPLATE_PATH: Path to the templates.
function copy_zippackage_S3() {
    local BUCKET_NAME="$1"
    local S3_TEMPLATE_PATH="$2"
    local PACKAGEPATH="$3"
    problem=true

    file=$(basename "$PACKAGEPATH")

    if [[ $file == *.zip ]]; then
        log "Zipped package: $file"
        #copy packageto bucket
        aws s3 cp \
        "$PACKAGEPATH" \
        "s3://${BUCKET_NAME}/${S3_TEMPLATE_PATH}/${file}"
        if [ $? -eq 0 ]; then
            log "Package $file copied to S3 successfully"
        else
            log "Failed to copy package $file to S3" "error"
            problem=false
        fi
    else
        log "Package $file is not zipped" "error"
        problem=false
    fi

    echo "$problem"
}

#copy templates to S3 Bucket
function copy_templates_S3Bucket() {
    local BUCKET_NAME="$1"
    local TMPL_PATH="$2"
    local REPO_NAME="$3"

    file=$(basename "$TMPL_PATH")

    log "Copy template to S3 Bucket: $file"

    aws s3 cp \
    "$TMPL_PATH" \
    "s3://${BUCKET_NAME}/$REPO_NAME/CFN/${file}"
    if [ $? -eq 0 ]; then
        log "Template $file copied to S3 successfully"
    else
        log "Failed to copy template $file to S3" "error"
    fi

}

function copy_ami_S3Bucket() {
    local BUCKET_NAME="$1"
    local REPO_NAME="$2"
    local REPO_PATH="$3"

    #check if the path "$REPO_PATH/.rpl/ami/s3" exist
    if [[ -d "$REPO_PATH/.rpl/ami/s3" ]]; then
        log "Copying all ami files to S3 Bucket"
        aws s3 cp \
        "$REPO_PATH/.rpl/ami/s3" \
        "s3://${BUCKET_NAME}/$REPO_NAME/ami/rpl" \
        --recursive
        result=$?
        if [ $result -eq 0 ]; then
            log "ami rpl files copied to S3 Bucket successfully"
        else
            log "Failed to copy ami rpl files to S3 Bucket" "error"
        fi
    fi

}

# Function that uploads changed files from folder scripts to S3 Bucket
# which would mimic the folders structure in main folder scripts
# The main S3 path is <BUCKET_NAME>/<REPO_NAME>/scripts/
function copy_scripts_S3Bucket() {
    local BUCKET_NAME="$1"
    local CHANGED_SCRIPTS="$2"
    local REPO_NAME="$3"
    local REPO_PATH="$4"
    local NEW_BUCKET="$5"

    #get setting if copy everything from scripts folder to bucket
    full_upload=$(get_config_value "SCRIPTS_FULL_UPLOAD" "$REPO_PATH")

    #check if new bucket was created
    #copy everything from scripts folder to bucket
    if [[ "$NEW_BUCKET" == "true" || "$full_upload" == "true" ]]; then
        log "Copying all files from scripts folder to S3 Bucket"
        aws s3 cp \
        "$REPO_PATH/scripts" \
        "s3://${BUCKET_NAME}/$REPO_NAME/scripts" \
        --recursive
        result=$?
        if [ $result -eq 0 ]; then
            log "Files copied to S3 Bucket successfully"
        else
            log "Failed to copy files to S3 Bucket" "error"
        fi
    else
        log "Copying only changed files from scripts folder to S3 Bucket"
        #COPY only changed files from scripts folder to bucket
        #go through list of files in $CHANGE_SCRIPTS and copy to bucket
        while read -r file_path  ; do
            log "Copying file: $file_path"
            #copy file to bucket
            aws s3 cp \
            "$REPO_PATH/$file_path" \
            "s3://${BUCKET_NAME}/$REPO_NAME/${file_path}"
            result=$?
            if [ $result -eq 0 ]; then
                log "Files copied to S3 Bucket successfully"
            else
                log "Failed to copy files to S3 Bucket" "error"

            fi
        done < "$REPO_PATH/$CHANGED_SCRIPTS"
    fi

}


# Deploys AWS CloudFormation templates
# Arguments:
#   $1: REPOPATH - The directory where the source code is located
#   $2: TMPL_PATH - The path to the CloudFormation template file
#   $3: STACKS - A list of existing CloudFormation stacks
#   $4: ACCOUNT - The AWS account to deploy the stack to
function deploy_templates() {
    local REPOPATH="$1"
    local TMPL_PATH="$2"
    local ACCOUNT="$3"
    local REGION="$4"
    local CNAME="$5"
    local stack_name="$6"
    local multi_stack="$7"
    local PARAMETERS="$8"
    set -x
    
    #Get template name from $TMPL_PATH
    filename=$(basename "$TMPL_PATH")
    name="${filename%.*}"

    log "Deploy template: $name"

    #Check if stack_name already exist

    check_stack "$stack_name" "$REGION" "$REPOPATH" "$multi_stack"
    retcode=$?
    if [[ ${retcode} -eq 1 ]]; then
        log "${ACCOUNT}, ${stack_name} deployment FAILED"
        add_final_results "${ACCOUNT} (${REGION}), ${stack_name}" "failed"
        return 1
    elif [[ ${retcode} -eq 2 ]]; then
        log "${ACCOUNT}, ${stack_name} deployment was skipped"
        add_final_results "${ACCOUNT} (${REGION}), ${stack_name}" "skipped"
        return 1
    fi
    log "Checking the template size"
    
    templatesize=$(stat -c%s "$TMPL_PATH")
    maxfile=51200
    log "Deploying template ${stack_name}"
    
    if [[ $templatesize -le maxfile ]]; then
    aws cloudformation deploy \
        --template-file "${TMPL_PATH}" \
        --stack-name "${stack_name}" \
        --region "$REGION" \
        --capabilities 'CAPABILITY_NAMED_IAM' 'CAPABILITY_AUTO_EXPAND' \
        --parameter-overrides $(echo "${PARAMETERS[@]}")
    else
    env=$(echo $ACCOUNT | cut -f1 -d-)
    aws cloudformation deploy \
        --template-file "${TMPL_PATH}" \
        --stack-name "${stack_name}" \
        --region "$REGION" \
        --capabilities 'CAPABILITY_NAMED_IAM' 'CAPABILITY_AUTO_EXPAND' \
        --s3-bucket $env-dbsql-rpl \
        --parameter-overrides $(echo "${PARAMETERS[@]}")
    fi   
        
    retcode=$?
    if [[ ${retcode} -ne 0 ]]; then
        add_final_results "${ACCOUNT} (${REGION}), ${stack_name}" "failed"
        log "${ACCOUNT}, ${stack_name} deployment FAILED!" "error"
    else
        add_final_results "${ACCOUNT} (${REGION}), ${stack_name}" "success"
        log "${ACCOUNT}, ${stack_name} deployment SUCCESS"
        
        #check if CNAME is not empty and if it is not empty then updat/create Route 53 record when stack is created
        if [[ "$CNAME" != "" ]]; then
            log "Waiting for deploy-stack command to complete..."
            while true; do
                CREATE_STACK_STATUS=$(aws --region "$REGION" cloudformation describe-stacks --stack-name "${stack_name}" --query 'Stacks[0].StackStatus' --output text)
                retcode=$?
                if [[ ${retcode} -ne 0 ]]; then
                    log "${ACCOUNT}, ${stack_name} describing stack FAILED"
                    return 1
                fi
                #check_route53
                case "${CREATE_STACK_STATUS}" in
                "CREATE_COMPLETE")
                    log "Stack creation completed..."
                    log "Getting hostname from stack ${stack_name}"

                    #Get VPC from ACCOUNT (second part of the account)
                    VPC=$(echo "${ACCOUNT}" | awk -F '-' '{print $2}')
                    #Get hosted zone name
                    hosted_zone_name="${VPC}.cnqr.tech"

                    ## Code to fetch hosted zone id
                    hosted_zone_id=$(get_hosted_zone_id "${VPC}" "${REGION}")
                    retcode=$?
                    if [[ ${retcode} -ne 0 ]]; then
                        log "Error: No hosted zone found in ${ACCOUNT}, ${REGION}"
                        add_final_results "${ACCOUNT} (${REGION}), ${stack_name} ${CNAME} CNAME issue" "failed"
                        return 1
                    fi
                    status=$(aws --region "$REGION" cloudformation describe-stacks --stack-name "${stack_name}")
                    #check if the stack_name has in name SolwEC2 and if it has then get the hostname from the stack from the output IntstanceDNSName
                    if [[ "$stack_name" == "SolwEC2"* ]]; then
                        hostname=$(echo "${status}" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="IntstanceDNSName") | .OutputValue')
                    else 
                        hostname=$(echo "${status}" | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="Master") | .OutputValue')
                    fi
                    if [[ -z "${hostname}" ]]; then
                        log "Error: No hostname found in stack '${stack_name}'"
                        add_final_results "${ACCOUNT} (${REGION}), ${stack_name} ${CNAME} CNAME issue" "failed"
                        return 1
                    fi
                    
                    if [[ "${stack_name}" == "$key"* ]]; then
                        log "Updating Route 53 record for '${CNAME}'"
                        cname_record_name="${CNAME}.${hosted_zone_name}"
                        update_route_53 "${hosted_zone_id}" "${cname_record_name}" "${hostname}"
                        return_status=$?
                        if [[ ${return_status} -ne 0 ]] ; then 
                            add_final_results "${ACCOUNT} 'CNAME ${cname_record_name}' is not assigned to Stack ${stack_name}" "failed"
                        else
                            add_final_results "${ACCOUNT} 'CNAME ${cname_record_name}' is assigned to Stack ${stack_name}" "success"
                        fi
                    fi 
                    break
                    ;;
                "CREATE_IN_PROGRESS"|"REVIEW_IN_PROGRESS")
                    # Wait 60 seconds and then check stack status again
                    sleep 60
                    ;;
                *)
                    echo "Stack creation failed with status ${CREATE_STACK_STATUS}"
                    exit 1
                    ;;
                esac
            done
        fi
    fi
}

#function command should find ARN for the policy,detach and  delete this policy and delete role.
#The policy MSSQLLambdaPolicy-SendNotification already exists on the role MSSQLLambdaRole-SendNotification.
function delete_role () {
    set -x
    local REGION="$1"
    local ERROR_MSG="$2"

    export https_proxy=proxy.service.cnqr.tech:3128
    export http_proxy=proxy.service.cnqr.tech:3128

    local result=""

    if [[ "$ERROR_MSG" =~ .*Role.*\ already\ exists.* || "$ERROR_MSG" =~ The\ policy\ .*already\ exists\ on\ the\ role\ .* ]]; then
        if [[ "$ERROR_MSG" =~ .*Role.*\ already\ exists.* ]]; then
            role_name=$(echo "$ERROR_MSG" | awk '{print $1}')
            policy_name=$(aws iam list-role-policies --role-name "$role_name" --ca-bundle /etc/pki/ca-trust/source/anchors/root.crt --output text)
            if [[ ! -z "$policy_name" ]]; then
                sleep 5
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" --region "$REGION" --ca-bundle /etc/pki/ca-trust/source/anchors/root.crt 
                sleep 5 
                aws iam delete-role --role-name "${role_name}" --region "$REGION" --ca-bundle /etc/pki/ca-trust/source/anchors/root.crt
                retcode=$?
                if [[ ${retcode} -ne 0 ]]; then
                    echo false
                else
                    echo true
                fi
            fi
        elif [[ "$ERROR_MSG" =~ The\ policy\ .*already\ exists\ on\ the\ role\ .* ]]; then
            role_name=$(echo "$ERROR_MSG" | awk -F 'role ' '{print $2}' | awk -F '.' '{print $1}')
            policy_name=$(echo "$ERROR_MSG" | awk -F 'policy ' '{print $2}' | awk -F ' ' '{print $1}')
            #if policy found detach and delete the policy
            if [[ ! -z "$policy_name" ]]; then
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" --region "$REGION" --ca-bundle /etc/pki/ca-trust/source/anchors/root.crt
                sleep 5
                aws iam delete-role --role-name "${role_name}" --region "$REGION" --ca-bundle /etc/pki/ca-trust/source/anchors/root.crt
                retcode=$?
                if [[ ${retcode} -ne 0 ]]; then
                    echo false
                else
                    echo true
                fi
            fi

        fi
    else
        echo false
    fi

    
}


# This function retrieves the templates that need to be deployed in a specific AWS account.
# It takes the changed templates with packages, changed bare templates, codebuild source directory as arguments.  
# It writes the paths of templates containing the account to either the templates zip or templates file.

# Parameters:
#   $1: The AWS account to retrieve the templates for.
#   $2: The file path of the file containing the changed templates with packages.
#   $3: The file path of the file containing the changed templates.
#   $4: The file path of the CodeBuild source directory.
function get_templates_for_deploy_in_account() {
    set -x
    local ACCOUNT="$1"
    local DEPLOY_TMPL="$2"
    local REPOPATH="$3"

    local templates="$REPOPATH/${ACCOUNT}_templates.out"
    touch "$templates"

    if [[ $(stat -c %s "${DEPLOY_TMPL}") -ge 2 ]]; then
        while read -r tmpl_path; do
            if [[ -z "$tmpl_path" ]]; then
                continue
            fi
            fullpath="$REPOPATH/$tmpl_path"
            filename=$(basename "$tmpl_path")
            template="${filename%.*}"
            found_account=$(search_account_in_template "$ACCOUNT" "$fullpath")
            if [[ $found_account == "$ACCOUNT" ]]
            then
                echo "$tmpl_path" >> "$templates"
            fi
        done < "$REPOPATH/$DEPLOY_TMPL"
    fi

}


function use_pckg_for_deploy() {
    set -x
    local tmpl_path="$1"
    local SUBFOLDERS_WITH_PKG="$2"
    local REPOPATH="$3"


    #get folder path
    folder_path=$(dirname "$tmpl_path")

    fullpath="$REPOPATH/$SUBFOLDERS_WITH_PKG"

    #check if SUBFOLDERS_WITH_PKG is empty
    if [[ $SUBFOLDERS_WITH_PKG != "" ]]; then
        #search if $folder_path is in list of folder pathes
        if grep -wq "$folder_path" "$fullpath"; then
            echo true
        else
            echo false
        fi
    else
        echo false
    fi

}

#THere can be created different type of stacks

#multi stack - stack can be deployed more times in one account:
#  1. Stack with custom parameters which is not scheduled for deploy has unique name given by key from parameter-value config file
#  2. Stack with custom parameters which is scheduled for deploy monthly (workstation) has unique name every month and more stacks are different by "key" values for same month
#  3. Stack without custom parameters which is scheduled for deploy randomly has unique name consiting from "key" and timestamp value

#not multi stack - stack can be deployed only once in one account:
#  1. #Stack is not multi stack and it does not have any custom parameter so stack name is same as template name
#  2. Stack without custom parameters (stack is expected only one with stack name given by template name)
#  3. #Stack is multi stack and it has custom parameters so stack name is template name + key
#  4. #Stack has entry in main config file where is mapping of template name and stack name
function create_stack_name() {
    set -x
    local REPOPATH="$1"
    local name="$2"
    local key="$3"
    local ACTION="$4"
    local INITIATOR="$5"
    local ACCOUNT="$6"

    
    multi_stack=$(search_in_config "MULTISTACK" "$name" "$REPOPATH")
    #if template is set multi stack in config file so it is possible to deploy more stacks with same template so unique stack name is needed
    if [[ $multi_stack == true ]]; then
        if [[ "$ACTION" == "ScheduleDeploy" && ($INITIATOR == "dbawksDeploy" || $INITIATOR == "dbawksDeployProd") ]]; then
            #Sheduled template deploying: Stack name has unique name every month and more stacks are different by "template name"-key for same month
            stack_name="${key}"-$(date +%b)$(date +%y)
        elif [[ "$ACTION" == "ScheduleDeployTest" && $INITIATOR == "dbsqlAMIIntTest" ]]; then
            stack_name="${key}-$(date +%s)"
        elif [[ "$ACTION" == "Deploy" || $INITIATOR == "MANUAL" ]]; then
            #Manual template deploying use key from parameter-value config file
            stack_name="${key}"
        else
            #Stack is multi stack and it does not have any custom parameter so stack name is same as template name
            #Create current timestamp for stack name
            stack_name="${name}-$(date +%s)"
        fi
    #Templates which are not multi stack are not scheduled for deploy
    elif [[ $multi_stack == false ]]; then

        #find if name of the template is in main config file so the defined stack name is used
        manual_stack_name=$(get_stack_name_in_account "$ACCOUNT" "$REPOPATH" "$name" )
        #test that there is return the value one
        status=$?
        if [ $status -eq 0 ]; then  
           stack_name="${manual_stack_name}" 
        #Stack is not multi stack and it does not have any custom parameter so stack name is same as template name
        elif [[ $key == '' ]]; then
            stack_name="${name}"
        
        else
            #Stack is multi stack and it has custom parameter so stack name is template name + key
            stack_name="${name}-${key}"
        fi
    fi
    echo "$stack_name"
}

function check_route53(){
    log "Before proxy"
    aws route53 list-hosted-zones  --region "${REGION}" --debug
    aws route53 list-hosted-zones-by-name --region "${REGION}" --debug
    log "After proxy"
    export HTTPS_PROXY="http://${PROXY_URL}:${PROXY_PORT}"
    export HTTP_PROXY="http://${PROXY_URL}:${PROXY_PORT}"
    echo $no_proxy
    aws route53 list-hosted-zones  --region "${REGION}" --no-verify-ssl --debug
}

 #Gets the Route53 hosted zone ID for the given VPC in the specified region.
 # @param {string} VPC - The VPC name 
 # @param {string} REGION - The AWS region
 # @returns {string} The hosted zone ID if found, error code 1 if not found
function get_hosted_zone_id(){
    local VPC="$1"
    local REGION="$2"
    export https_proxy="${PROXY_URL}:${PROXY_PORT}"

    export AWS_CA_BUNDLE="/etc/pki/ca-trust/source/anchors/root.crt"
    #export http_proxy="${PROXY_URL}:${PROXY_PORT}"
    local hosted_zone_name="$VPC.cnqr.tech"
    local hosted_zone_id=$(aws route53 list-hosted-zones  --region "${REGION}" | jq -r '.HostedZones[] | select(.Name=="'${hosted_zone_name}'.") | .Id')
    if [ -z "$hosted_zone_id" ]; then
        return 1
    fi
    hosted_zone_id=${hosted_zone_id##*/}
    echo "${hosted_zone_id}"
    return 0
}



function update_route_53(){
    local hosted_zone_id=$1
    local cname_record_name=$2
    local hostname=$3
    #export http_proxy="${PROXY_URL}:${PROXY_PORT}"
    export AWS_CA_BUNDLE="/etc/pki/ca-trust/source/anchors/root.crt"
    export https_proxy="${PROXY_URL}:${PROXY_PORT}"
    aws route53 change-resource-record-sets --hosted-zone-id "${hosted_zone_id}" \
            --change-batch '{
                "Changes": [
                    {
                        "Action": "UPSERT",
                        "ResourceRecordSet": {
                            "Name": "'"${cname_record_name}"'",
                            "Type": "CNAME",
                            "TTL": 300,
                            "ResourceRecords": [
                                {
                                    "Value": "'"${hostname}"'"
                                }
                            ]
                        }
                    }
                ]
            }' 2>&1 > /dev/null
    if [[ $? -eq 0 ]] ; then
        return 0
    else
        return 1
    fi
}


# Checks the status of an AWS CloudFormation stack and performs actions based on the stack's status.
# @param {string} STACK_NAME - The name of the CloudFormation stack to check.
# @param {string} REGION - The AWS region where the CloudFormation stack is located.
# @param {string} REPOPATH - The repository path where the CloudFormation template is located.
# @param {boolean} multi_stack - Indicates whether the stack is part of a multi-stack type.
# @returns {number} - 0 if the stack does not exist or has been deleted, 1 if the stack exists and is in a valid state.


function check_stack()
{
    set -x
    local STACK_NAME="$1"
    local REGION="$2"
    local REPOPATH="$3"
    local multi_stack="$4"
    
    #get status of the stack
    response=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "$REGION" 2>&1) 
    echo "$response"
    #in case that stack is multi stack so return 0 if stack does not exist otherwise return 1
    if [[ $multi_stack == true ]]; then
        #check if stack does not exist
        if [[ $(echo "$response" | grep -c "does not exist") -ge 1 ]] ; then
        #Stack does not exist
        return 0
        elif [[ $(echo "$response" | grep -c "does not exist") -eq 0 ]] ; then
            #Stack exists
            stack_status=$(echo "${response}" | jq -r '.Stacks[0].StackStatus')
            #Check if stack is in all FAILED status except UPDATE_ROLLBACK_FAILED
            if [[ "$stack_status" == "CREATE_FAILED" || "$stack_status" == "ROLLBACK_FAILED" || "$stack_status" == "DELETE_FAILED" || "$stack_status" == "ROLLBACK_COMPLETE" || "$stack_status" == "ROLLBACK_IN_PROGRESS" ]]; then
                # Delete the stack
                log "AWS template in ${ACCOUNT} and region ${REGION}, ${STACK_NAME} in FAILED or ROLLBACK State!! - Deleting" "warning"
                aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"     
                aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 
                return 0
            else
                log "AWS template in ${ACCOUNT} and region ${REGION}, ${STACK_NAME} in ${stack_status} State!!" "info"
                #Find in config setting if stack must be deleted if exist before creation
                delete_stack=$(search_in_config "STACKTODELETE" "$STACK_NAME" "$REPOPATH")

                if [[ "${delete_stack}" == true ]]; then
                    # Delete the stack
                    log "Deleting ${STACK_NAME} template before deploying in account ${ACCOUNT} and region ${REGION}"
                    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 
                    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
                    return 0
                else
                    return 1
                fi
            fi
        fi
    else
        #Stack is not multi_stack so it can be updated
        #check if stack does not exist
        if [[ $(echo "$response" | grep -c "does not exist") -ge 1 ]] ; then
            #Stack does not exist
            return 0
        elif [[ $(echo "$response" | grep -c "does not exist") -eq 0 ]] ; then

            stack_status=$(echo "${response}" | jq -r '.Stacks[0].StackStatus')
            if [[ "$stack_status" == "CREATE_FAILED"  || "$stack_status" == "ROLLBACK_COMPLETE" ]]; then
                # Delete the stack
                log "AWS template in ${ACCOUNT} and region ${REGION}, ${STACK_NAME} in FAILED or ROLLBACK State!! - Deleting" "warning"
                aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"     
                aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 
                return 0
            else
                log "AWS template in ${ACCOUNT} and region ${REGION}, ${STACK_NAME} in ${stack_status} State!!" "info"
                #Find in config setting if stack must be deleted if exist before creation
                delete_stack=$(search_in_config "STACKTODELETE" "$STACK_NAME" "$REPOPATH")

                if [[ "${delete_stack}" == true ]]; then
                    # Delete the stack
                    log "Deleting ${STACK_NAME} template before deploying in account ${ACCOUNT} and region ${REGION}"
                    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 
                    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
                    return 0
                #stacks exists for UPDATE
                elif [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" || "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" || "$stack_status" == "IMPORT_COMPLETE" || "$stack_status" == "UPDATE_ROLLBACK_FAILED" || "$stack_status" == "UPDATE_FAILED" ]]; then
                    return 0
                else
                    return 2
                fi
      
            fi
        fi
    fi
}
