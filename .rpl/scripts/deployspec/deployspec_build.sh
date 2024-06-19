#!/usr/bin/env bash

. .rpl/scripts/functions.sh
. .rpl/scripts/functions_aws.sh
set -x
declare -r RPL_AWS_PARTITION="$1"
declare RPL_MULTI_TARGET_ACCOUNTS_IDS="$(<RPL_MULTI_TARGET_ACCOUNTS_IDS.out)"
declare CODEBUILD_BUILD_NUMBER=$(<CODEBUILD_BUILD_NUMBER.out)
declare REPO_NAME=$(<REPO_NAME.out)
declare ENVIRONMENT=$(<ENVIRONMENT.out)
declare TEMPLATES_FOLDER=$(<TEMPLATES_FOLDER.out)
declare SUBFOLDERS_WITH_PKG="SUBFOLDERS_WITH_PKG.out"
declare DEPLOY_TMPL="DEPLOY_TMPL.out"
declare S3_TEMPLATE_PATH=$REPO_NAME/$TEMPLATES_FOLDER
declare BUCKET_NAME=$(<BUCKET_NAME.out)
declare INITIATOR=$(<INITIATOR.out)
declare ACTION=$(<ACTION.out)


log "##################### build STARTED #####################"

#ITERATE PER ACCOUNT
IFS=' ' read -a multiAccounts <<< "${RPL_MULTI_TARGET_ACCOUNTS_IDS}" #Create an array of account IDs
for acc in "${multiAccounts[@]}"
do
    
    #Return environment-account , ex. integration-tools
    account=$(get_account_info "$acc" "$CODEBUILD_SRC_DIR")
    ENV=$(get_environment "$acc" "$CODEBUILD_SRC_DIR")
 

    region=$(get_environment_values $ENV $CODEBUILD_SRC_DIR "region")


    log "Account is ${account}, region $region assuming the deployer role in target account "
    assume_role "$acc" "$REPO_NAME" "$RPL_AWS_PARTITION" "$region"
    
    ########################################################################

    #Find which templates to build in given account
    #Return "${account}_templates.out
    log "Check if there are templates for deployment..."
    get_templates_for_deploy_in_account "${account}" "${DEPLOY_TMPL}" "${CODEBUILD_SRC_DIR}"

    ########################################################################
    # Deploying templates 
    log "Starting with templates deploying..."

    #Check if there are templates to deploy
    if [ -s "${account}_templates.out" ]; then
        #Iterate over templates
        while read tmpl_path  ; do

            #Get template name from $tmpl_path
            filename=$(basename "$tmpl_path")
            name="${filename%.*}"

            #check if tmpl_path is in file content stored in SUBFOLDERS_WITH_PKG
            use_pckg=$(use_pckg_for_deploy "$tmpl_path" "$SUBFOLDERS_WITH_PKG" "$CODEBUILD_SRC_DIR")
            #check if template is multi-stack->can be deployed more times in one account
            multi_stack=$(search_in_config "MULTISTACK" "$name" "$CODEBUILD_SRC_DIR")

            mandatory_parameters_values=()
            #Get mandatory parameters from template and assign values to them
            mandatory_parameters_values=($(get_mandatory_parameters_values "$CODEBUILD_SRC_DIR" "$tmpl_path" $use_pckg $REPO_NAME $account $BUCKET_NAME $S3_TEMPLATE_PATH $CODEBUILD_BUILD_NUMBER "${ACTION}"))
            status=$?
            if [ $status -ne 0 ]; then
                add_final_results "${account} (${region}), ${name}" "failed"
                #skip deployment
                continue
            fi

            #check if there are custom parameters
            custom_parameters=()
            custom_parameters=($(get_custom_parameters_from_template "$tmpl_path" "$CODEBUILD_SRC_DIR" $use_pckg))
            
            #there is need to be mandatory parameter-value config file if there are used custom parameters
            if [ ${#custom_parameters[@]} -ge 1 ];
            then   
                #get custom parameter-value file
                custom_parameter_value_file=$(get_custom_parameter_value_file "$tmpl_path" "$CODEBUILD_SRC_DIR" "$REPO_NAME" )
                status=$?
                if [ $status -ne 0 ]; then
                    add_final_results "${account} (${region}), ${name}" "failed"
                    #skip deployment
                    continue
                fi
            elif [ ${#custom_parameters[@]} -eq 0 ];
            then
                #if there no custom parameters but there is custom parameter-value file due to next sub keys (CNAME, ACTION, ACCOUNT)
                custom_parameter_value_file=$(get_custom_parameter_value_file "$tmpl_path" "$CODEBUILD_SRC_DIR" "$REPO_NAME" )
                status=$?
                if [ $status -ne 0 ]; then
                    custom_parameter_value_file=""
                fi
            fi
            #get keys from the custom parameter-value file which corresponds to action which starts the deployment process
            #return keys are identifiers for entries to deploy for the current action (Deploy or ScheduleDeploy)

            #Deploy only these entries which are for given action and for account for which is done deployment

            if [[ $custom_parameter_value_file != "" ]]; then
                keys=()
                if [[ $multi_stack == true ]]; then
                    #multi stack templates can be deployed more times in one account
                    #every deployment can have different values in parameter for entries in parameter-value file
                    keys=($(get_key_entries_for_action_account "$custom_parameter_value_file" "$CODEBUILD_SRC_DIR" $ACTION $account $ENV))
                    status=$?
                    if [[ $status -eq 1 ]]; then
                        add_final_results "${account} (${region}), ${name}" "skipped"
                        continue
                    fi
                else
                    #if template is not multi-stack so deploy only once
                    #then there is not checked ACTION and ACCOUNT from custom parameter-value file
                    #and deploy all of them as they can not be scheduled and they are always deployed according account list in template                      
                    keys=($(get_key_entries "$custom_parameter_value_file" "$CODEBUILD_SRC_DIR" $ENV))
                    status=$?
                    if [[ $status -eq 1 ]]; then
                        add_final_results "${account} (${region}), ${name}" "skipped"
                        continue
                    fi
                fi

                parameter_overrides=()
                custom_parameters_values=()

                #test if keys are empty
                if [ ${#keys[@]} -ge 1 ]; then
                    log "Deploying template with custom parameters.."

                    #Deploy template for every entry in config file with custom parameters
                    for key in "${keys[@]}"; 
                    do
                        #assign values to custom parameters
                        custom_parameters_values=()
                        custom_parameters_values=($(assign_values_to_custom_parameters "$custom_parameter_value_file" "$key" $ENV))
                        status=$?
                        if [ $status -ne 0 ]; then
                            add_final_results "${account} (${region}), ${name}" "failed"
                            continue
                        fi

                        #get together mandatory and custom parameters for parameter-overrides
                        parameter_overrides=($(get_parameter_overrides "${mandatory_parameters_values[*]}" "${custom_parameters_values[*]}"))

                        #Get CNAME if exist there for given entry in custom parameter-value file
                        CNAME=$(get_CNAME_for_key "$custom_parameter_value_file" "$CODEBUILD_SRC_DIR" "$key" "$ENV")
                        status=$?
                        if [ $status -ne 0 ]; then
                            #template does not have set CNAME value or it does not use it (usually only used for workstations and servers)
                            CNAME=""
                        fi

                        stack_name=$(create_stack_name "$CODEBUILD_SRC_DIR" "$name" "$key" "$ACTION" "$INITIATOR" "$account" )
                        log "Deploying templates in account ${account} and region ${region}..."
                        deploy_templates "$CODEBUILD_SRC_DIR" "$tmpl_path" "$account" "$region" "$CNAME" "$stack_name" "$multi_stack" "${parameter_overrides[*]}" &
                    done
                else
                    #not found entries for deploy or schedule deploy
                    add_final_results "${account} (${region}), ${name}" "skipped"
                    log "No entries for deploy or schedule deploy in ${account} and region ${region}." "info"
                    continue
                fi
            else
                #config file not found so deploy with only mandatory parameters which are same in account
                log "Deploying with only mandatory parameters"
                log "Deploying templates in account ${account} and region ${region}..."
                CNAME=""
                key=""

                #get together mandatory and custom parameters for parameter-overrides
                parameter_overrides=($(get_parameter_overrides "${mandatory_parameters_values[*]}" "${custom_parameters_values[*]}"))                    
                stack_name=$(create_stack_name "$CODEBUILD_SRC_DIR" "$name" "$key" "$ACTION" "$INITIATOR" "$account" )
                deploy_templates "$CODEBUILD_SRC_DIR" "$tmpl_path" "$account" "$region" "$CNAME" "$stack_name" "$multi_stack" "${parameter_overrides[*]}" &
            fi
                
        done <  "${account}_templates.out"
        # Wait for all the templates  to deploy
        wait
        log "Deploying templates in ${account} FINISHED."

    else
        add_final_results "${account} (${region}) No templates to deploy" "skipped"
        log "No templates to deploy in ${account}." "warning"
        continue   
    fi
done 

send_final_result "${CODEBUILD_BUILD_NUMBER}" "${ENVIRONMENT}" "${REPO_NAME}"

log "##################### build FINISHED #####################"
exit 0
