#!/usr/bin/env bash



#Import the function to test
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions.sh
source /Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft/.rpl/scripts/functions_aws.sh
set -x

#tmpl_path="templates/LicenseManager/MSSQLRAM-ResourceShareTest.yml"
tmpl_path="templates/Workstations/MSSQLEC2-DBAWKS-Domain.json"
#tmpl_path="templates/MSSQLSG-MssqlFsx.yaml"
#tmpl_path="templates/FIPS-1node-DPA-MySQL.yaml"
#tmpl_path="templates/MYSQLIAM-MYSQLOpsRole.yaml"
CODEBUILD_SRC_DIR="/Users/i346175/Library/CloudStorage/OneDrive-SAPSE/GITHUB/RplRepoDraft"
use_pckg=false
REPO_NAME="RPLRepoDraft"
account="integration-tools"
BUCKET_NAME="integration-dbsql-shared"
S3_TEMPLATE_PATH="RPLREPODRAFT/templates/"
CODEBUILD_BUILD_NUMBER=300
#create file TEMPLATES_MASTER.out

TEMPLATES_MASTER="TEMPLATES_MASTER.out"
ACTION="ScheduleDeploy"
region="us-west-2"
INITIATOR="MANUAL"


ENV=$(get_environment "957236237862" "$CODEBUILD_SRC_DIR")


filename=$(basename "$tmpl_path")
name="${filename%.*}"


multi_stack=$(search_in_config "MULTISTACK" "$name" "$CODEBUILD_SRC_DIR")

mandatory_parameters_values=()
#Get mandatory parameters from template and assign values to them
mandatory_parameters_values=($(get_mandatory_parameters_values "$CODEBUILD_SRC_DIR" "$tmpl_path" $use_pckg $REPO_NAME $account $BUCKET_NAME $S3_TEMPLATE_PATH $CODEBUILD_BUILD_NUMBER "${ACTION}"))

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
        exit
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
#Difference between one time deployment and regular deployment is in the way how to get keys?
#what about these templates which does not have custom parameters?

if [[ $custom_parameter_value_file != "" ]]; then
    keys=()
    if [[ $multi_stack == true ]]; then
        #multi stack templates can be deployed more times in one account
        #every deployment can have different values in parameter for entries in parameter-value file
        keys=($(get_key_entries_for_action_account "$custom_parameter_value_file" "$CODEBUILD_SRC_DIR" $ACTION $account $ENV))
        status=$?
        if [ $status -eq 1 ]; then
            add_final_results "${account} (${region}), ${name}" "skipped"
            exit
        fi
    else
        #if template is not multi-stack so deploy only once
        #then there is not checked ACTION and ACCOUNT from custom parameter-value file
        #and deploy all of them as they can not be scheduled and they are always deployed according account list in template                      
        keys=($(get_key_entries "$custom_parameter_value_file" "$CODEBUILD_SRC_DIR" $ENV))
        status=$?
        if [ $status -ne 0 ]; then
            slack_notify "Failed to get keys for ${account} (${region}), ${filename}" "error"
            add_final_results "${account} (${region}), ${name}" "failed"
            exit
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
                slack_notify "Failed to assign values to custom parameters for ${account} (${region}), ${name}" "error"
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

            stack_name=$(create_stack_name "$CODEBUILD_SRC_DIR" "$name" "$key" "$ACTION" "$INITIATOR" )

            log "Deploying templates in account ${account} and region ${region}..."
            deploy_templates "$CODEBUILD_SRC_DIR" "$tmpl_path" "$account" "$region" "$CNAME" "$stack_name" "$multi_stack" "${parameter_overrides[*]}" &
        done
    else
        #not found entries for deploy or schedule deploy
        add_final_results "${account} (${region}), ${name}" "skipped"
        log "No entries for deploy or schedule deploy in ${account} and region ${region}." "info"
        exit
    fi
else
    #config file not found so deploy with only mandatory parameters which are same in account
    log "Deploying with only mandatory parameters"
    log "Deploying templates in account ${account} and region ${region}..."
    CNAME=""
    key=""

    #get together mandatory and custom parameters for parameter-overrides
    parameter_overrides=($(get_parameter_overrides "${mandatory_parameters_values[*]}" "${custom_parameters_values[*]}"))
    
    stack_name=$(create_stack_name "$CODEBUILD_SRC_DIR" "$name" "$key" "$ACTION" "$INITIATOR" )

    deploy_templates "$CODEBUILD_SRC_DIR" "$tmpl_path" "$account" "$region" "$CNAME" "$stack_name" "$multi_stack" "${parameter_overrides[*]}" &

fi
wait

send_final_result "${CODEBUILD_BUILD_NUMBER}" "${ENVIRONMENT}" "${REPO_NAME}"

log "##################### build FINISHED #####################"

rm skipped.out
rm success.out
rm failed.out