#!/usr/bin/env bash
# This is a shell file containing additional functions that are helping in the process of deployment.


# Function for logging the progress of build and deployment.
# Params:
# - LOG_MESSAGE: Message that needs to be logged.
# - LOG_TYPE: Tyepe of log message. (info, warning, error) The default value is set to be info message. (OPTIONAL)
function log() {  
    local LOG_MESSAGE=$1
    local LOG_TYPE=$2
    local CURRENT_DATE=$(date +'%Y/%m/%d %H:%M:%S')

    local lowercase=$(echo "$LOG_TYPE" | tr '[:upper:]' '[:lower:]')

    case $lowercase in
    "info")
        log_level="[INFO]"
        ;;
    "warning")
        log_level="[WARNING]"
        ;;
    "error")
        log_level="[ERROR]"
        ;;
    *)
        log_level="[INFO]"
        ;;
    esac

    printf "\n [%s] [dbsql] %s - %s \n" "$CURRENT_DATE" "$log_level" "$LOG_MESSAGE"
}

# Function: get_config_value
# Description: Retrieves the value of a specified key from the config.json file.
# Parameters:
#   - KEY: The key to retrieve the value for.
#   - CODEBUILD_SRC_DIR: The directory path where the config.json file is located.
# Returns:
#   - The value associated with the specified key.
function get_config_value() {
    local KEY="$1"
    local REPOPATH="$2"

    value=$(jq -r ".[\"$KEY\"]" "${REPOPATH}/.rpl/files/config.json")
    echo $value
}

# Function: search_in_config
# Description: Searches for a specific value in a JSON configuration file.
# Parameters:
#   - KEY: The key to search for in the JSON file.
#   - VALUE: The value to search for within the specified key.
#   - CODEBUILD_SRC_DIR: The directory path where the JSON file is located.
# Returns:
#   - true: If the specified value is found within the specified key in the JSON file.
#   - false: If the specified value is not found within the specified key in the JSON file.
function search_in_config {
    local KEY="$1"
    local VALUE="$2"
    local REPOPATH="$3"

    value=$(jq -r ".\"${KEY}\"[]" "${REPOPATH}/.rpl/files/config.json" | grep -wq "$VALUE")
    if [ $? -eq 0 ]; then
        echo true
    else
        echo false
    fi
}



# Function: get_key_entries
# Description: Retrieves the keys from a JSON file and returns them as an array.
# Parameters:
#   - $1: CUSTOM_PARAMETER_VALUE_FILE - The path to the JSON file.
# Returns:
#   - An array containing the keys from the JSON file.
function get_key_entries() {
    local CUSTOM_PARAMETER_VALUE_FILE=$1
    local REPO_PATH="$2"
    local ENVIRONMENT=$3

    #get config name from CUSTOM_PARAMETER_VALUE_FILE
    filename=$(basename -- "$REPO_PATH/$CUSTOM_PARAMETER_VALUE_FILE")
    
    keys=$(jq -r --arg env "$ENVIRONMENT" '.[$env] | keys[]' "$REPO_PATH/$CUSTOM_PARAMETER_VALUE_FILE")
    if [ $? -ne 0 ]; then
        return 1
    elif [ -z "$keys" ]; then
        return 1
    else
        echo "${keys[@]}"
        return 0
    fi
}


function get_key_entries_for_action_account() {
    local CUSTOM_PARAMETER_VALUE_FILE=$1
    local REPO_PATH="$2"
    local ACTION=$3
    local ACCOUNT=$4
    local ENVIRONMENT=$5

    #get config name from CUSTOM_PARAMETER_VALUE_FILE
    filename=$(basename -- "$REPO_PATH/$CUSTOM_PARAMETER_VALUE_FILE")
    
    keys=$(jq -r --arg env "$ENVIRONMENT" --arg action "$ACTION" --arg account "$ACCOUNT" '.[$env] | to_entries[] | select(.value.Parameters.Action==$action and .value.Parameters.Account==$account) | .key' "$REPO_PATH/$CUSTOM_PARAMETER_VALUE_FILE")
    if [ $? -ne 0 ]; then
        #test if keys contain text "null (null) has no keys"
        if [[ $keys == *"null (null) has no keys"* ]]; then
            return 2
        else
            return 1
        fi
    elif [ -z "$keys" ]; then
        return 1
    else
        echo "${keys[@]}"
        return 0
    fi
}

function get_CNAME_for_key() {
    local CUSTOM_PARAMETER_VALUE_FILE=$1
    local REPO_PATH="$2"
    local KEY=$3
    local ENVIRONMENT=$4

    # Use jq to parse the JSON and extract the CNAME value for the given key
    local CNAME=$(jq -r ".\"${ENVIRONMENT}\".\"${KEY}\".\"CNAME\"" "$REPO_PATH/$CUSTOM_PARAMETER_VALUE_FILE")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    if [[ $CNAME == "null" ]]; then
        CNAME=""
        echo "$CNAME"
        return 0
    else
        echo "$CNAME"
        return 0
    fi
    
}


# Function: search_account_in_template
# Description: Searches for an account value in the Account.AllowedValues 
# parameter of a CloudFormation template file.
# Parameters:
#   VALUE: The account value to search for
#   TEMPLATE_PATH: The path to the CloudFormation template file
# Returns: 
#   The matching AllowedValue if found, false otherwise

function search_account_in_template {
    local VALUE=$1
    local TEMPLATE_PATH=$2

    #get file name from TEMPLATE_PATH
    filename=$(basename -- "$TEMPLATE_PATH")
    #get extension from filename
    extension="${filename##*.}"
    if [[ $extension == "yaml" || $extension == "yml" ]]; then
        foundvalue=$(yq eval ".Parameters.Account.AllowedValues.[] | select(. == \"$VALUE\")" "$TEMPLATE_PATH")
    elif [[ $extension == "json" ]]; then
        foundvalue=$(jq -r ".Parameters.Account.AllowedValues[] | select(. == \"$VALUE\")" "$TEMPLATE_PATH")
    fi
    
    if [ -z "$foundvalue" ]; then
        echo false 
    else
        echo $foundvalue
    fi
}

function search_action_in_template {
    local VALUE=$1
    local TEMPLATE_PATH=$2

    #get file name from TEMPLATE_PATH
    filename=$(basename -- "$TEMPLATE_PATH")
    #get extension from filename
    extension="${filename##*.}"
    if [[ $extension == "yaml" || $extension == "yml" ]]; then
        #firstly find if .Parameters.Action exist
        foundvalue=$(yq eval ".Parameters.Action.AllowedValues.[] | select(. == \"$VALUE\")" "$TEMPLATE_PATH")
    elif [[ $extension == "json" ]]; then
        foundvalue=$(jq -r ".Parameters.Action.AllowedValues[] | select(. == \"$VALUE\")" "$TEMPLATE_PATH")
    fi
    
    if [ -z "$foundvalue" ]; then
        echo false 
    else
        echo $foundvalue
    fi
}

function get_action_in_template {
    local TEMPLATE_PATH=$1
    actions=()

    #get file name from TEMPLATE_PATH
    filename=$(basename -- "$TEMPLATE_PATH")
    #get extension from filename
    extension="${filename##*.}"
    if [[ $extension == "yaml" || $extension == "yml" ]]; then
        #firstly find if .Parameters.Action exist
        actions=$(yq eval '.Parameters.Action.AllowedValues.[]' "$TEMPLATE_PATH")

    elif [[ $extension == "json" ]]; then
        actions=$(jq -r '.Parameters.Action.AllowedValues[]' "$TEMPLATE_PATH")

    fi
    
    if [ -z "$actions" ]; then
        echo false 
    else
        echo "${actions[*]}"
    fi
}

# Search if template nests templates (nested templates)
# Search for "AWS::CloudFormation::Stack" in template file
function search_nested_templates() {
    local TMPL_PATH=$1
    local result=false

    if grep -wq "AWS::CloudFormation::Stack" "$TMPL_PATH"; then
        result=true
    fi
    
    echo $result
}

function get_maintemplate_in_template {
    local TEMPLATE_PATH=$1

    #get file name from TEMPLATE_PATH
    filename=$(basename -- "$TEMPLATE_PATH")
    #get extension from filename
    extension="${filename##*.}"
    if [[ $extension == "yaml" || $extension == "yml" ]]; then
        foundvalue=$(yq eval ".Parameters.MainTemplate.AllowedValues.[]" "$TEMPLATE_PATH")
    elif [[ $extension == "json" ]]; then
        foundvalue=$(jq -r ".Parameters.MainTemplate.AllowedValues[]" "$TEMPLATE_PATH")
    fi
    
    if [ -z "$foundvalue" ]; then
        echo false 
    else
        echo $foundvalue
    fi
}

function get_parameters_from_template {
    local TMPL_PATH=$1
    local REPO_PATH=$2
    parameters=()
    set -x

    #get file name from TEMPLATE_PATH
    filename=$(basename -- "$TMPL_PATH")
    #get extension from filename
    extension="${filename##*.}"
    if [[ $extension == "yaml" || $extension == "yml" ]]; then
        #get list of Parameter names without their values and properties from yaml file
        parameters=($(yq eval '.Parameters | keys | join(" ")' "$REPO_PATH/$TMPL_PATH"))
    elif [[ $extension == "json" ]]; then
        parameters=($(jq -r '.Parameters | keys | join(" ")' "$REPO_PATH/$TMPL_PATH"))
    fi
    
    echo "${parameters[*]}"
    
}

function get_custom_parameters_from_template {
    local TMPL_PATH=$1
    local REPO_PATH=$2
    local USE_PKG=$3
    local custom_parameters=()

    set -x

    #get file name from TEMPLATE_PATH
    filename=$(basename -- "$TMPL_PATH")
    #get extension from filename
    extension="${filename##*.}"
    if [[ $extension == "yaml" || $extension == "yml" ]]; then     
       #get parameters which are not "Account" and "Package" and "Path" and "BucketName" and "Version"
        if [[ $USE_PKG == true ]]; then
            read -r -a custom_parameters <<< $(yq eval '.Parameters | keys | map(select(. != "Account" and . != "Package" and . != "Path" and . != "BucketName" and . != "Version" and . != "Action")) | join(" ")' "$REPO_PATH/$TMPL_PATH")

        elif [[ $USE_PKG == false ]]; then
            read -r -a custom_parameters <<< $(yq eval '.Parameters | keys | map(select(. != "Account" and . != "Action" and . != "BucketName")) | join(" ")' "$REPO_PATH/$TMPL_PATH")
        fi
    elif [[ $extension == "json" ]]; then
        if [[ $USE_PKG == true ]]; then
            #get parameters which are not "Account" and "Package" and "Path" and "BucketName" and "Version"
            custom_parameters=($(jq -r '."Parameters" | to_entries[] | select(.key != "Account" and .key != "Package" and .key != "Path" and .key != "BucketName" and .key != "Version" and .key != "Action") | .key' "$REPO_PATH/$TMPL_PATH"))
        
        elif [[ $USE_PKG == false ]]; then    
            #get parameters which are not "Account" and "Package" and "Path" and "Version" and "Action"
            custom_parameters=($(jq -r '."Parameters" | to_entries[] | select(.key != "Account" and .key != "Action" and .key != "BucketName" ) | .key' "$REPO_PATH/$TMPL_PATH"))     
        fi
    fi

    echo "${custom_parameters[*]}"
}

create_parameter_file () {
    local TMPL_PATH=$1
    
    #get dirname from TMPL_PATH
    folder_path=$(dirname "$TMPL_PATH")
    #get filename from tmpl_path
    filename=$(basename "$TMPL_PATH")
    #get file name without extension
    template="${filename%.*}"
    #set parameter file name
    parameter_file="${folder_path}/${template}-params.txt"
    touch "$parameter_file"
    echo "$parameter_file"
}

get_parameter_file () {
    local TMPL_PATH=$1
    #get dirname from TMPL_PATH
    folder_path=$(dirname "$TMPL_PATH")
    #get filename from tmpl_path
    filename=$(basename "$TMPL_PATH")
    #get file name without extension
    template="${filename%.*}"
    #set parameter file name
    parameter_file="${folder_path}/${template}-params.txt"
    #check if parameter file exist
    if [[ ! -f "$parameter_file" ]]; then
        return 0
    fi
    
    echo "$parameter_file"
}

get_mandatory_parameters_values() {
    local REPOPATH=$1
    local TMPL_PATH=$2
    local USE_PCKG=$3
    local REPO_NAME=$4
    local ACCOUNT=$5 
    local BUCKET_NAME=$6
    local S3_TEMPLATE_PATH=$7
    local CODEBUILD_BUILD_NUMBER=$8
    local ACTION=${9}
    set -x
    
    template_path="$REPOPATH/$TMPL_PATH"
    #get the folder where is the template_path
    folder_path=$(dirname "$template_path")
    #get file from template_path
    filename=$(basename -- "$template_path")
    extension="${filename##*.}"
    #get file name without extension
    template_name="${filename%.*}"


    #check if output contain mandatory parameters 
    if [[ $USE_PCKG == true ]]; then
        if [[ $extension == "yaml" || $extension == "yml" ]]; then     
            read -r -a parameters <<< $(yq eval '.Parameters | keys | map(select(. == "Account" or . == "Package" or . == "Path" or . == "Version" or . == "BucketName" or . == "Action") | join(" ")' "$template_path")
            if [ ${#parameters[@]} -eq 0 ]; then
                log "Template $template_path does not contain all required parameters" "error"
                slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n Build Skipped \n Add mandatory parameters."
                return 1
            fi
    
        elif [[ $extension == "json" ]]; then
            readarray -t parameters < <(jq -r '.Parameters | keys[] | select(. == "Account" or . == "Package" or . == "Path" or . == "BucketName" or . == "Version" or . == "Action")' "$template_path")
            if [ ${#parameters[@]} -eq 0 ]; then
                log "Template $template_path does not contain all required parameters" "error"
                slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n Build Skipped \n Add mandatory parameters."
                return 1
            fi
            
        else
            log "Template $template_path has an invalid extension" "error"      
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name has an invalid extension - Build Skipped \n Fix it please."
            return 1
        fi
    elif [[ $USE_PCKG == false ]]; then
        #template is not with additional package

        #get mandatory parameters Account, BucketName, Action
        if [[ $extension == "yaml" || $extension == "yml" ]]; then     
            read -r -a parameters <<< $(yq eval '.Parameters | keys | map(select(. == "Account" or . == "BucketName" or . == "Action")) | join(" ")' "$template_path")
            if [ ${#parameters[@]} -eq 0 ]; then
                log "Template $template_path does not contain all required parameters" "error"
                slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n Build Skipped \n Add mandatory parameters."
                return 1
            fi
        elif [[ $extension == "json" ]]; then
            readarray -t parameters < <(jq -r '.Parameters | keys[] | select(. == "Account" or . == "BucketName" or . == "Action")' "$template_path")

            if [ ${#parameters[@]} -eq 0 ]; then
                log "Template $template_path does not contain all required parameters" "error"
                slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n Build Skipped \n Add mandatory parameters."
                return 1
            fi
        else
            log "Template $template_path has an invalid extension" "error"      
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name has an invalid extension - Build Skipped \n Fix it please."
            return 1
        fi 

    fi


    #Iterate through the parameters array  and replace the placeholders with the actual values provided by parameters function
    for i in "${!parameters[@]}"; do
        if [[ ${parameters[i]} == "Account" ]]; then
            parameters[i]="${parameters[i]}=$ACCOUNT"
        elif [[ ${parameters[i]} == "BucketName" ]]; then
            parameters[i]="${parameters[i]}=$BUCKET_NAME"
        elif [[ ${parameters[i]} == "Version" ]]; then
            parameters[i]="${parameters[i]}=$CODEBUILD_BUILD_NUMBER"
        elif [[ ${parameters[i]} == "Path" ]]; then
            parameters[i]="${parameters[i]}=$S3_TEMPLATE_PATH"
        elif [[ ${parameters[i]} == "Action" ]]; then
            parameters[i]="${parameters[i]}=$ACTION"
        elif [[ ${parameters[i]} == "Package" ]]; then
            parameters[i]="${parameters[i]}=$template_name"
        fi
    done

    echo "${parameters[@]}"
    return 0

}

check_parameters() { 
    local TMPL_PATH=$1
    local REPO_NAME=$2
    local REPO_PATH=$3
    local SUBFOLDERS_WITH_PKG=$4
    local ENV=$5
    local problem=false
    custom_parameters=()
    parameters=()
    actions=()
    template_master=""
    template_to_S3bucket=""
    template_for_deploy=""
    set -x

    #check if file TEMPLATES_TO_S3BUCKET.out exist if not create it
    if [[ ! -f "TEMPLATES_TO_S3BUCKET.out" ]]; then
        touch "TEMPLATES_TO_S3BUCKET.out"
    fi
    #check if file TEMPLATES_FOR_DEPLOY.out exist if not create it
    if [[ ! -f "TEMPLATES_FOR_DEPLOY.out" ]]; then
        touch "TEMPLATES_FOR_DEPLOY.out"
    fi
    
    
    #return all parameters from template
    parameters=($(get_parameters_from_template "$TMPL_PATH" "$REPO_PATH"))
    
    #get the folder where is the template_path
    folder_path=$(dirname "$TMPL_PATH")
    #get file from template_path
    filename=$(basename -- "$TMPL_PATH")
    extension="${filename##*.}"
    #get file name without extension
    template_name="${filename%.*}"

    #check if parameters contain parameter Action
    if [[ "${parameters[*]} " =~ "Action" ]]; then         
        #Get template content and if there is parameter Action in cloudformation template with Allowevalue S3Bucket.
        actions=($(get_action_in_template "$TMPL_PATH"))
        if [[ "${actions[*]} " =~ 'S3Bucket' ]]; then
            log "Template file $file_name contain value 'S3Bucket' for parameter Action" "info"
            template_to_S3bucket="$TMPL_PATH"
            store_variables "TEMPLATES_TO_S3BUCKET" "$template_to_S3bucket"
        fi
        if [[ "${actions[*]} " =~ 'Deploy' ]]; then
            #Get template content and if there is parameter Action in cloudformation template with Allowevalue CloudFormation.
            log "Template file $file_name contain value 'Deploy' for parameter Action" "info"
            template_for_deploy="$TMPL_PATH"
            store_variables "TEMPLATES_FOR_DEPLOY" "$template_for_deploy"
        fi
        if [[ "${actions[*]} " =~ 'ScheduleDeploy' ]]; then
            #Get template content and if there is parameter Action in cloudformation template with Allowevalue CloudFormation.
            log "Template file $file_name contain value 'ScheduleDeploy' for parameter Action" "info"
            template_for_schedule_deploy="$TMPL_PATH"
            store_variables "TEMPLATES_FOR_SCHEDULE_DEPLOY" "$template_for_schedule_deploy"
        fi
        #Search if template nests templates (nested templates)
        result=$(search_nested_templates "$TMPL_PATH")
        if [[ $result == true ]]; then
            template_master="$TMPL_PATH"
            store_variables "TEMPLATES_MASTER" "$template_master"
        fi
    fi

    #check if tmpl_path is in list SUBFOLDERS_WITH_PKG
    if [[ " ${SUBFOLDERS_WITH_PKG[*]} " == *" "${folder_path}" "* ]]; then
        #check if parameters contain parameter Account
        if [[ ! " ${parameters[*]} " =~ "Account" ]]; then
            log "Template $template_path does not contain required parameter Account" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Account."
            problem=true
        fi
        #check if parameters contain parameter Package
        if [[ ! " ${parameters[*]} " =~ "Package" ]]; then
            log "Template $template_path does not contain required parameter Package" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Package."
            problem=true
        fi
        #check if parameters contain parameter Path
        if [[ ! " ${parameters[*]} " =~ "Path" ]]; then
            log "Template $template_path does not contain required parameter Path" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Path."
            problem=true
        fi
        #check if parameters contain parameter BucketName
        if [[ ! " ${parameters[*]} " =~ "BucketName" ]]; then
            log "Template $template_path does not contain required parameter BucketName" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter BucketName."
            problem=true
        fi
        #check if parameters contain parameter Version
        if [[ ! " ${parameters[*]} " =~ "Version" ]]; then
            log "Template $template_path does not contain required parameter Version" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Version."
            problem=true
        fi
        #check if parameters contain parameter Action
        if [[ ! " ${parameters[*]} " =~ "Action" ]]; then
            log "Template $template_path does not contain required parameter Action" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Action."
            problem=true
        fi
    elif [[ $template_master == "" ]]; then
        #check if parameters contain parameter Account
        if [[ ! " ${parameters[*]} " =~ "Account" ]]; then
            log "Template $template_path does not contain required parameter Account" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Account."
            problem=true
        fi
        #check if parameters contain parameter Action
        if [[ ! " ${parameters[*]} " =~ "Action" ]]; then
            log "Template $template_path does not contain required parameter Action" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Action."
            problem=true
        fi
    else
        #check if parameters contain parameter Account
        if [[ ! " ${parameters[*]} " =~ "Account" ]]; then
            log "Template $template_path does not contain required parameter Account" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Account."
            problem=true
        fi
        #check if parameters contain parameter Action
        if [[ ! " ${parameters[*]} " =~ "Action" ]]; then
            log "Template $template_path does not contain required parameter Action" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter Action."
            problem=true
        fi
        #check if parameters contain parameter BucketName where are stored nested templates
        if [[ ! " ${parameters[*]} " =~ "BucketName" ]]; then
            log "Template $template_path does not contain required parameter BucketName" "error"
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template_name does not contain required parameters \n - Build Skipped \n Add parameter BucketName."
            problem=true
        fi
    fi

    #check if cfn template is nested
    #nested file must be always stored to S3 bucket
    if [[ $template_to_S3bucket == "" ]]; then
        
        use_pckg=$(use_pckg_for_deploy "$tmpl_path" "$SUBFOLDERS_WITH_PKG" "$REPO_PATH")  
        #check custom parameters for master cfn templates or for templates which does not nest other templates
        custom_parameters=()
        custom_parameters=($(get_custom_parameters_from_template "$TMPL_PATH" "$REPO_PATH" "$use_pckg"))

        #check if there are custom parameters and tmpl_path is master template
        if [[ "${custom_parameters[*]}" != "" && $template_master != "" ]]; then
            #get custom parameter-value file
            custom_parameter_value_file=$(get_custom_parameter_value_file "$TMPL_PATH" "$REPO_PATH" "$REPO_NAME")
            status=$?
            if [ $status -ne 0 ]; then
                slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "The parameter-value config file not found for template $template_name \n Build Skipped \n Create parameter-value config file."
                return 1
            fi
        fi

        #found problem during checking parameters
        if [[ $problem == true ]]; then
            return 1
        else
            echo "${actions[*]}"
            return 0
        fi

    fi
}

function assign_values_to_mandatory_parameters() {
    set -x
    local ACCOUNT=$1
    local BUCKET_NAME=$2
    local S3_TEMPLATE_PATH=$3
    local TMPL_PATH=$4
    local VERSION=$5
    local USE_PCKG=$6
    local REPO_PATH=$7

    local ACTION='Deploy'

    parameters_file=$(get_parameter_file "$TMPL_PATH")
    status=$?
    if [ $status -ne 0 ]; then
        return 1
    fi

    #Get template name from $TMPL_PATH path
    template=$(basename "$TMPL_PATH")
    template_name="${template%.*}"

    #exchange values in <> by values from parameters $ACCOUNT, $ACTION
    #or from ACCOUNT, BUCKET_NAME, S3_TEMPLATE_PATH, PACKAGE, VERSION, $ACTION
    #in case USE_PCKG is true
    if [[ $USE_PCKG == true ]]; then
        # Use sed to replace the placeholder in the parameters_file with the extracted value
        if ! sed -i "s@<Account>@$ACCOUNT@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Account> in $parameters_file" "error"
            return 1
        fi
        if ! sed -i "s@<BucketName>@$BUCKET_NAME@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <BucketName> in $parameters_file" "error"
            return 1
        fi
        if ! sed -i "s@<Path>@$S3_TEMPLATE_PATH@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Path> in $parameters_file" "error"
            return 1
        fi
        if ! sed -i "s@<Package>@$template_name@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Package> in $parameters_file" "error"
            return 1
        fi
        if ! sed -i "s@<Version>@$VERSION@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Version> in $parameters_file" "error"
            return 1
        fi
        if ! sed -i "s@<Action>@$ACTION@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Action> in $parameters_file" "error"
            return 1
        fi
    elif [[ $USE_PCKG == false ]]; then
        if ! sed -i "s@<Account>@$ACCOUNT@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Account> in $parameters_file" "error"
            return 1
        fi
        if ! sed -i "s@<Action>@$ACTION@g" "$REPO_PATH/$parameters_file"; then
            log "Failed to replace <Action> in $parameters_file" "error"
            return 1
        fi
    else
        log "The parameter USE_PCKG has invalid value" "error"
        return 1
    fi

    echo "$parameters_file"
    return 0
}


function get_custom_parameter_value_file() {
    local TMPL_PATH=$1
    local REPO_PATH=$2
    local REPO_NAME=$3

    custom_parameter_value_file=""
    
    #get dirname from tmpl_path
    folder_path=$(dirname "$TMPL_PATH")

    #find the specific file naem if more of them is found
    #get filename from tmpl_path
    filename=$(basename "$TMPL_PATH")
    #get file name without extension
    template="${filename%.*}"
    #get expected custom parameter value file name
    custom_parameter_value_file="$REPO_PATH/$folder_path/${template}.config"

    if [[ -f "$custom_parameter_value_file" ]]
    then
        chmod 777 "$custom_parameter_value_file"
        echo "$folder_path/${template}.config"
        return 0
    else
        log "The parameter-value config file does not exist" "failed"
        return 1
    fi
}

   

function assign_values_to_custom_parameters() {
    set -x
    local CUSTOM_PARAMETER_VALUE_FILE=$1
    local KEY=$2
    local ENVIRONMENT=$3

    #create variable with name $paramz-$key
    declare -a "paramz"

    mapfile -t paramz < <(jq -r --arg env "$ENVIRONMENT" --arg key "$KEY" '.[$env] | .[$key]?.Parameters | to_entries[] | "\(.key)=\(.value)"' "$CUSTOM_PARAMETER_VALUE_FILE")
    if [[ ${#paramz[@]} -eq 0 ]]; then
        log "The parameter-value config file does not contain any searched key \"$KEY\"" "failed"
        return 1
    fi

    echo "${paramz[@]}"
    return 0
}
    
#Function get_parameter-overrides
#It takes as parameters two arrays and returns one array
function get_parameter_overrides() {
    local MANDATORY_PARAMETERS_VALUES=$1
    local CUSTOM_PARAMETERS_VALUES=$2

    #create new array from MANDATORY_PARAMETERS_VALUES and CUSTOM_PARAMETERS_VALUES arrays
    declare -a "parameter_overrides"
    #is ${CUSTOM_PARAMETERS_VALUES[@]}" empty then assign only MANDATORY_PARAMETERS_VALUES to parameter_overrides

    if [[ ${#CUSTOM_PARAMETERS_VALUES[@]} -eq 0 ]]; then
        parameter_overrides=("${MANDATORY_PARAMETERS_VALUES[@]}")
        echo "${parameter_overrides[@]}"
        return 0
    else
        parameter_overrides=("${MANDATORY_PARAMETERS_VALUES[@]}" "${CUSTOM_PARAMETERS_VALUES[@]}")
        echo "${parameter_overrides[@]}"
        return 0
    fi
}

# Function: get_account_info
# Description: Retrieves account information based on the provided account ID.
# Parameters:
#   - ACC: The account ID.
#   - CODEBUILD_SRC_DIR: The directory path where the config.json file is located.
# Returns:
#   - The concatenated string of environment and account name.
function get_account_info() {
    local ACC="$1"
    local CODEBUILD_SRC_DIR="$2"
    local account_info
    local account_name
    local environment

    account_info=$(jq -r --arg ACC "$ACC" '.ACCOUNT[] | select(.account_id == $ACC)' "$CODEBUILD_SRC_DIR"/.rpl/files/config.json)
    account_name=$(echo $account_info | jq -r '.account_name')
    environment=$(echo $account_info | jq -r '.environment')
    echo "${environment}-${account_name}"
}

function get_environment_values() {
    local ENVIRONMENT=$1
    local REPOPATH=$2
    local KEY="$3"

    local value

    value=$(jq -r --arg ENVIRONMENT "$ENVIRONMENT" --arg KEY "$KEY" '.ENVIRONMENT[$ENVIRONMENT][$KEY]' "$REPOPATH"/.rpl/files/config.json)
    #make value lower case
    echo "$value" | tr '[:upper:]' '[:lower:]'
}


get_slack_value_for_key() {
    local KEY=$1
    local REPOPATH=$2
    local value
    value=$(jq -r --arg key "$KEY" '.SLACK[$key]' "$REPOPATH"/.rpl/files/config.json)
    echo "$value"
}



get_schedule_type_config_value() {
    local NAME="$1"
    local REPOPATH="$2"


    #find TYPE from key SCHEDULE in config file
    schedule_name=$(jq -r ".SCHEDULE[\"$NAME\"]" "$REPOPATH"/.rpl/files/config.json)
    schedule_type=$(echo $schedule_name | jq -r '.TYPE')
    echo "$schedule_type"
}


# Function: get_account_value_for_key
# Description: Get value for given parameter for given account from the config.json file.
# Parameters:
#   - ACCOUNT: The account name.
#   - REPOPATH: The path to the repository.
#   - KEY: The key to retrieve the value for.
# Returns:
#   - Return the value associated with a given account for given KEY from the config.json file.
get_account_value_for_key() {
    local ACCOUNT=$1
    local REPOPATH="$2"
    local KEY="$3"
    local value
    
    value=$(jq -r --arg ACCOUNT "$ACCOUNT" --arg KEY "$KEY" '.ACCOUNT[$ACCOUNT][$KEY]' "$REPOPATH"/.rpl/files/config.json)
    echo "$value"
}

#Function get_stack_name_in_account
#Decription: Get stack name for given account from the config.json file
#Parameters: 
#   - ACCOUNT: The account name.
#   - REPOPATH: The path to the repository.
#   - TEMPLATE: The template name for which is found stack name
#Returns:
#   - Return the stack name associated with a given account for given template from the config.json file.
# JSON Structure:

#      "integration-tools": {
#            "account_name": "tools", 
#            "environment": "integration",
#            "account_id": "957236237862",
#            "manual_stack_names": {
#                "MSSQLIAM-MSSQLOpsRole": "MSSQLOpsRole",
#                "MSSQLSG-dbsqlRole": "create-mssqlSG"
#            }

get_stack_name_in_account() {
    local ACCOUNT=$1
    local REPOPATH="$2"
    local TEMPLATE="$3"
    local stack_name

    stack_name=$(jq -r --arg ACCOUNT "$ACCOUNT" --arg TEMPLATE "$TEMPLATE" '.ACCOUNT[$ACCOUNT].manual_stack_names[$TEMPLATE]' "$REPOPATH"/.rpl/files/config.json)
    #test that stack_name is null

    if [[ $stack_name == "null" ]]; then
        return 1
    else
        echo "$stack_name"
        return 0
    fi
}

# Function: get_environment
# Description: Retrieves the environment associated with the given account ID.
# Parameters:
#   - ACC: The account ID.
#   - CODEBUILD_SRC_DIR: The directory path where the config.json file is located.
# Returns:
#   - The environment associated with the account ID in lowercase.
function get_environment() {
    local ACC="$1"
    local CODEBUILD_SRC_DIR="$2"
    local environment

    account_info=$(jq -r --arg ACC "$ACC" '.ACCOUNT[] | select(.account_id == $ACC)' "$CODEBUILD_SRC_DIR"/.rpl/files/config.json)
    environment=$(echo $account_info | jq -r '.environment')
    #make environment lower case
    echo "$environment" | tr '[:upper:]' '[:lower:]'
}


# Function: set_branch_info
# Description: Sets the branch information by retrieving the branch details from the config.json file.
# Parameters:
#   - branch: The name of the branch
# Returns: None
function set_branch_info() {
    local branch="$1"
    local REPOPATH="$2"
    branch_info=$(jq -r ".BRANCH[\"$branch\"]" "$REPOPATH"/.rpl/files/config.json)
    target_envs=$(echo $branch_info | jq -r '.TARGET_ENVS')
    environment=$(echo $branch_info | jq -r '.ENVIRONMENT')
    store_variables "TARGET_ENVS" "$target_envs"
    store_variables "ENVIRONMENT" "$environment"
}

check_templates() {
    local FOLDER_PATH="$1"
    local REPO_NAME="$2"
    local problem=false

    for file_path in $(find $FOLDER_PATH -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \)); do
        file_name=$(basename -- "$file_path")
        template="${file_name%.*}"
        #get folder path
        folder_path=$(dirname "$file_path")
        #get folder from folder_path
        folder=$(basename "$folder_path")

        #check if template has name from which can be created STACK
        if [[ ${#template} -lt 1 || ${#template} -gt 100 ]]; then
            log "Template $template has a name length not between 1 and 100 characters" "error"
            # Sends a Slack notification  
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template has a name length not between 1 and 128 characters - Build Skipped \n Fix it please."
            problem=true
        fi

        if [[ ! $template =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            log "Template $template does not start with an alphabetic character or includes not allowed characters" "error"
            # Sends a Slack notification  
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template does not start with an alphabetic character or includes not allowed characters - Build Skipped \n Fix it please."
            problem=true
        fi

        if [[ $template =~ ["\\/?:*\`<>|[\]{}#%~&"] ]]; then
            log "Template $template includes one of the disallowed characters" "error"
            # Sends a Slack notification  
            slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "Template $template includes one of the disallowed characters - Build Skipped \n Fix it please."
            problem=true
        fi

        #does folder_path contain python files with extension 'py' or powershell 'ps1' together with yaml/yml/json files
        if [[ $folder_path != "/$folder" ]]; then
            if find "$folder_path" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) -print0 | grep -qz ".*" && find "$folder_path" -maxdepth 1 -type f \( -name "*.py" -o -name "*.ps1"  \) -print0 | grep -qz ".*" ; then
                #count how many json,yml,yaml is in $subfolder
                count=$(find "$folder_path" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) | wc -l)
                #if number of files is not equal 1 give error message otherwise process it
                if [[ $count -ne 1  ]]; then
                    log "Only one yaml/yml/json file must be stored in subfolder if additional code is used $folder_path" "error"
                    # Sends a Slack notification  
                    slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "$folder_path: Only one template must be in subfolder with additional code file - Build Skipped \n Fix number of yml/yaml/json files in $folder_path subfolder"
                    problem=true
                fi
            fi
        elif [[ $folder_path == "/$folder" ]]; then
        #check if main folder contain python files with extension 'py' or powershell 'ps1'
            if find "$folder_path" -maxdepth 1 -type f \( -name "*.py" -o -name "*.ps1"  \) -print0 | grep -qz ".*" ; then
                log "Python or Powershell code must be stored in subfolder" "error"
                # Sends a Slack notification  
                slack_notify "$REPO_NAME: AWS template check FAILED" "danger" "$folder_path: Python or Powershell code must be stored in subfolder - Build Skipped \n Fix it please."
                problem=true
            fi
        fi

        if [[ $problem == true ]]
        then
            return 1
        fi
    done
}

#return list of folders where is python or powershell code
get_folders_with_additional_code ()
{
    local FOLDER_PATH="$1"
    local REPO_NAME="$2"
    subfolders_with_pkg=""
    #find all subfolders with python or powershell code and store all pathes
    for file_path in $(find "$FOLDER_PATH" -type f \( -name "*.py" -o -name "*.ps1" \)); do
        #ger $folder_path from $file_path
        folder_path=$(dirname "$file_path")
        subfolder_name=$(basename -- "$folder_path")
            # Check if the subfolder was already processed
        if [[ -n "${processed_dirs[$subfolder_name]}" ]]; then
            continue
        fi

        subfolders_with_pkg="$subfolders_with_pkg""$folder_path"$'\n'
         # Store the subfolder name in the processed_dirs array to avoid processing duplicate subfolders
        processed_dirs[$subfolder_name]=1
    done


    store_variables 'SUBFOLDERS_WITH_PKG' "$(echo "$subfolders_with_pkg" | sed '/^$/d')"

    #return subfolders_with_pkg as list
    echo "${subfolders_with_pkg[*]}"

}

function scan_templates() {
    set -x
    local TEMPLATES_FOLDER="$1"
    local REPOPATH="$2"
    local REPO_NAME="$3"
    local TEMPLATESZIP="$4"
    local VERSION="$5"
    local ACTION="$6"
    local issue=0
    local -A processed_dirs
    local subfolders_with_pkg

    #change context to repository folder
    #cd "$REPOPATH" || exit 1

    #check if file CHANGED_TPL.out exist if not create it
    if [[ ! -f "DEPLOY_TMPL.out" ]]; then
        touch "DEPLOY_TMPL.out"
    fi

    #check if templates have names usable for STACK creation and check if templates and additonal codes are stored correctly in subfolder
    check_templates "$TEMPLATES_FOLDER" "$REPO_NAME"
    #return list of folders where is python or powershell code
    subfolders_with_pkg=$(get_folders_with_additional_code "$TEMPLATES_FOLDER" "$REPO_NAME")

    count=0
    #Go through list of template files
    while IFS= read -r tmpl_path ; do
        if [[ -z "$tmpl_path" ]]; then
                continue
        fi
        count=$((count + 1))
        #get file name from tmpl_path
        file_name=$(basename -- "$tmpl_path")
        #get file name without extension
        template_name="${file_name%.*}"
        #get folder path
        folder_path=$(dirname "$tmpl_path")

        #check parameters in template
        #Get what actions should be done with the template. Possibilities:  deploy, scheduledeploy or for storing to S3 Bucket
        actions=($(check_parameters "$tmpl_path" "$REPO_NAME" "$REPOPATH" "$subfolders_with_pkg"))
        status=$?
        if [ $status -ne 0 ]; then  
            #add 1 to variable issue
            issue=$((issue + 1))
            continue;
        fi

        #if issue appers thand stop deployment
        if [[ $issue -ne 0 ]]; then
            log "There are issues with templates" "error"
            exit
        fi
        
        #check if template use additional code by checking if tmpl_path is in subfolders_with_pkg
        if [[ " ${subfolders_with_pkg[*]} " == *" "${folder_path}" "* ]]; then
            subfolder_name=$(basename -- "$folder_path")
             # Check if the subfolder was already processed
            if [[ -n "${processed_dirs[$subfolder_name]}" ]]; then
                continue
            fi

            #check if template is scheduled to be deploy so zip additional code although nothing was changed
            #If template can be scheduled and current ACTION is SheduleDeploy* as well so zip packages if it has some
            #zip additional code for template
           if [[ "${actions[*]} " =~ "ScheduleDeploy"* && $ACTION == "ScheduleDeploy"* ]]; then
                zip_packages "$VERSION" "$tmpl_path" "$TEMPLATESZIP" "$REPOPATH"
                status=$?
                if [ $status -ne 0 ]; then
                    slack_notify "$REPO_NAME: Zipping operation FAILED" "danger" "The zip operation of additional code for template $template_name failed \n Build Skipped \n Check the log for issue."
                    continue
                fi
                # Store the subfolder name in the processed_dirs array to avoid processing duplicate subfolders
                processed_dirs[$subfolder_name]=1
                                    
                #store templates path which will be deployed
                deploy_tmpl_files_path="$deploy_tmpl_files_path""$tmpl_path"$'\n'               
            
            #check if template is for deploy and it was changed or its configuration file, additional code (python or powershell) was changed
            #zip additional code for template

            elif [[ $(grep -w -e "$tmpl_path" -e "$folder_path/.*\.ps1" -e "$folder_path/.*\.py" -e "$folder_path/$template_name.config" CHANGED_FILES.out) && "${actions[*]} " =~ "Deploy" ]]; then
                
                zip_packages "$VERSION" "$tmpl_path" "$TEMPLATESZIP" "$REPOPATH"
                status=$?
                if [ $status -ne 0 ]; then
                    slack_notify "$REPO_NAME: Zipping operation FAILED" "danger" "The zip operation of additional code for template $template_name failed \n Build Skipped \n Check the log for issue."
                    continue
                fi
                # Store the subfolder name in the processed_dirs array to avoid processing duplicate subfolders
                processed_dirs[$subfolder_name]=1
                                    
                #store templates path which will be deployed
                deploy_tmpl_files_path="$deploy_tmpl_files_path""$tmpl_path"$'\n'
            fi
        #template is not in subfolder with additional code
        else
            #check if template is scheduled to be deploy
            #ACTION is scheduled from EventBridge
            if [[ "${actions[*]} " =~ "ScheduleDeploy"* && $ACTION == "ScheduleDeploy"*  ]]; then
                deploy_tmpl_files_path="$deploy_tmpl_files_path""$tmpl_path"$'\n'
            #check if template is for deploy and it was changed or its configuration file was changed
            elif [[ $(grep -w -e "$tmpl_path" -e "$folder_path/$template_name.config" CHANGED_FILES.out) &&  "${actions[*]} " =~ "Deploy" ]]; then
                deploy_tmpl_files_path="$deploy_tmpl_files_path""$tmpl_path"$'\n'
            fi
        fi
    
    done < <(find "$TEMPLATES_FOLDER" -maxdepth 2 -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \))

    store_variables "DEPLOY_TMPL" "$deploy_tmpl_files_path"


    if [[ $count -eq 0 ]]; then
        # Logs a warning that no yaml/yml/json files was found
        log "No yml/yaml/json file found in $TEMPLATES_FOLDER and its subfolders" "error"
        
        # Sends a Slack notification  
        slack_notify "${REPO_NAME}: AWS template check FAILED" "danger" "$TEMPLATES_FOLDER and subfolders, No yaml/yml/json Found - Build Skipped \n Check if yml/yaml/json file exist in folder $TEMPLATES_FOLDER and its subfolder(s)"
        exit 1
    fi
}

function scan_scripts() {
    set -x
    local SCRIPTS_FOLDER="$1"
    local REPOPATH="$2"
    local REPO_NAME="$3"
    #define list of changed scripts
    local -a CHANGED_SCRIPTS_LIST=""
    local CHANGED_SCRIPTS=""
    

    #change context to repository folder
    cd "$REPOPATH" || exit 1


    CHANGED_SCRIPTS_LIST=($(grep -w -e "$SCRIPTS_FOLDER" CHANGED_FILES.out))
    status=$?
    if [ $status -ne 0 ]; then
        log "No changed scripts files found in $SCRIPTS_FOLDER" "error"
    else
        log "Changed scripts files found in $SCRIPTS_FOLDER" "info"
        #Go through list of script files in CHANGED_SCRIPTS_LIST array
        #store path of changed script files in CHANGED_SCRIPTS variable and store it in CHANGED_SCRIPTS.out file
        #every path is stored in new line
        for script_path in "${CHANGED_SCRIPTS_LIST[@]}"; do
            if [[ -z "$script_path" ]]; then
                continue
            fi
            #store path of changed script files in CHANGED_SCRIPTS variable
            CHANGED_SCRIPTS="$CHANGED_SCRIPTS""$script_path"$'\n'
        done

        #store scripts path which will be deployed
        store_variables "CHANGED_SCRIPTS" "$CHANGED_SCRIPTS"
        #print out the list of changed scripts from CHANGED_SCRIPTS.out file
        log "Changed scripts: $(<CHANGED_SCRIPTS.out)"

    fi

}
        

# Function to store variables that can after be used accross all the build/deployment 
# The value of the stored variable then can be read by reading the file in another variable like $(<TARGET_ENVS.out).
# The out file has to be set to a name of the variable.
# Params: 
# - NAME: Name of the variable to store.
# - VALUE: Value for the variable. 
function store_variables() {

    local -r NAME="$1"
    local -r VALUE="$2"
    local filename="${NAME}.out"
    echo "${VALUE}" >> "$filename"
}


# Function for adding a final results in out files that can be then send as a notification
# in the last step of a deployment
# Params:
# - MESSAGE: Message that is stored in out file. Each on a new line.
# - TYPE: Type of message. Determines to which file is message saved. Type of files are skipped, success, failed
function add_final_results() {
    
    local MESSAGE="$1"
    local TYPE="$2"
    local skippedFile="skipped.out"
    local successFile="success.out"
    local failedFile="failed.out"    


    case $TYPE in
    "skipped")
        if [ ! -f "$skippedFile" ]; then
        touch "$skippedFile"
        fi
        echo -e "\n$MESSAGE" >> "$skippedFile"
        ;;
    "success")
        if [ ! -f "$successFile" ]; then
        touch "$successFile"
        fi
        echo -e "\n$MESSAGE" >> "$successFile"
        ;;
    "failed")
        if [ ! -f "$failedFile" ]; then
        touch "$failedFile"
        fi
        echo -e "\n$MESSAGE" >> "$failedFile"
        ;;
    *)
        log "Invalid input when adding final results." "error"
        ;;
    esac

}


# Function to send notification to a slack chanel.
# Params:
# - TITLE: Title of the slack message.
# - TYPE: Sets the type of slack message bu adding color to the side of the slack message. (good, danger, warning)
# - MESSAGE: Message of the slack message.
# - CHANNEL: Slack channel where message will be posted. (OPTIONAL)
# - SLACK_HOOK: Slack web hook for preferred slack channel. (OPTIONAL)
function slack_notify() {

    set -x
    # 1. Parameters & variables
    local SLACK_CHANNEL_CONFIG=$(get_slack_value_for_key "SLACK_CHANNEL" "$CODEBUILD_SRC_DIR")
    local SLACK_WEBHOOK_URL_CONFIG=$(get_slack_value_for_key "SLACK_HOOK" "$CODEBUILD_SRC_DIR")
    local TITLE="${1}"
    local TYPE="${2}"
    local MESSAGE="${3}"
    local CHANNEL=${4:-$SLACK_CHANNEL_CONFIG}
    local SLACK_HOOK=${5:-$SLACK_WEBHOOK_URL_CONFIG}
    local PROXYURL="proxy.service.cnqr.tech"
    local PORT="3128"
    local ACCOUNT_BUILD_NUMBER=$(echo $CODEBUILD_BUILD_ARN | cut -d':' -f5)

    if [ "${SLACK_WEBHOOK_URL_CONFIG}" == "" ] && [ "${SLACK_HOOK}" == "" ]; then
        log "Missing environment variable SLACK_HOOK" "error"
        exit 1
    fi
    if [ "${SLACK_CHANNEL_CONFIG}" == "" ] && [ "${CHANNEL}" == "" ]; then
        log "Missing environment variable SLACK_CHANNEL" "error"
        exit 1
    fi

    FOOTER="<${CODEBUILD_BUILD_URL}|LOGS>"
    FOOTER="<${CODEBUILD_BUILD_URL}|LOGS>"
    ATTACHMENT_CONTENT="{ \"color\":\"${TYPE}\", \"text\":\"${MESSAGE}\" , \"footer\":\"${FOOTER}\" }"

    # 2. Send message to Slack via Webhook URL
    # if the account number is build account number then no proxy is used
    if [[ $ACCOUNT_BUILD_NUMBER == "966799970081" ]]; then
        curl -k -X POST --data-urlencode \
        "payload={\"channel\": \"${CHANNEL}\", \"text\":\"${TITLE}\", attachments:[${ATTACHMENT_CONTENT}] }" \
            "${SLACK_HOOK}"
    else
        PROXY_URL="${PROXYURL}"
        PROXY_PORT="${PORT}"
        log "Sending message to Slack channel ${CHANNEL} : ${MESSAGE}"
        curl -k -X POST --data-urlencode \
            "payload={\"channel\": \"${CHANNEL}\", \"text\":\"${TITLE}\", attachments:[${ATTACHMENT_CONTENT}] }" \
            --proxy "${PROXY_URL}":"${PROXY_PORT}" "${SLACK_HOOK}"
    fi
}


# Zip subfolders where templates (yaml/yml/json) and python (py) or powershell (ps1) files are located
# The subfolders are listed in SUBFOLDERS_WITH_PKG.out file
# The zipped files are stored in the 'TemplatesZip' directory in the format subfolder_name.zip
# Params:
# - CODEBUILD_BUILD_NUMBER: Number of current build.
# - SUBFOLDERS_WITH_PKG: List of subfolders pathes that contain python files with extension 'py' or powershell file 'ps1'
# - TEMPLATESZIP: Name of directory where the zipped files are stored
# - REPOPATH: Name of root folder for current build
function zip_packages() {
    set -x
    local VERSION=$1
    local TMPL_PATH=$2
    local TEMPLATESZIP=$3
    local REPOPATH=$4

    #get folder path
    folder_path=$(dirname "$TMPL_PATH")
    subfolder_name=$(basename -- "$folder_path")
    #get folder from folder_path
    folder=$(basename "$folder_path")
    #get template name
    file_name=$(basename -- "$TMPL_PATH")
    template_name="${file_name%.*}"

    # Zip the currentfolder and exclude yaml/yml/md/json files
    #Store full path
    currentfolder="$REPOPATH/$folder_path"
    log "Zipping .py or .ps1 code in $subfolder_name with ${template_name}-${VERSION}.zip name" 
    #Create folder TEMPLATESZIP if not exist
    if [[ ! -d "$REPOPATH/$TEMPLATESZIP" ]]; then
        mkdir -p "$REPOPATH/$TEMPLATESZIP"
    fi
    
    cd "$currentfolder"
    zip -r "$REPOPATH/$TEMPLATESZIP/${template_name}-${VERSION}.zip" * -i "*.py" -i "*.ps1"
    #test if zip was success
    if [ $? -eq 0 ]; then
        log "Zipping .py or .ps1 code in $subfolder_name with '${template_name}-${VERSION}.zip' name was success"
        return 0
    else
        log "Zipping .py or .ps1 code in $subfolder_name with ${template_name}-${VERSION}.zip name was not success" "error"
        #slack error in zipping
        slack_notify "$REPO_NAME: Zipping additional template code FAILED" "danger" " Build Skipped \n Check log for details."
        return 1
    fi
    cd "$OLDPWD" || exit 1
}


# Function for sending the final results of deployment as a grouped message in the slack chanel.
# Params:
# - CODEBUILD_BUILD_NUMBER: Number of current build.
# - ENVIRONMENT: Name of AWS environment.
function send_final_result() {

    local CODEBUILD_BUILD_NUMBER=$1
    local ENVIRONMENT=$2
    local REPO_NAME=$3
    local skippedFile="skipped.out"
    local successFile="success.out"
    local failedFile="failed.out"

    if [ -f "$successFile" ]; then
    file_content=$(<"$successFile")
    slack_notify "${REPO_NAME} - SUCCESS Build Number: ${CODEBUILD_BUILD_NUMBER} Env: ${ENVIRONMENT}" "good" "${file_content}"


    log "${file_content}"
    else
        log "File not found: $successFile" "warning"
    fi

    if [ -f "$failedFile" ]; then
        file_content=$(<"$failedFile")
        slack_notify "${REPO_NAME} - FAILED Build Number: ${CODEBUILD_BUILD_NUMBER} Env: ${ENVIRONMENT}" "danger" "${file_content}"

        log "${file_content}"
    else
        log "File not found: $failedFile" "warning"
    fi

    if [ -f "$skippedFile" ]; then
        file_content=$(<"$skippedFile")
        slack_notify "${REPO_NAME} - SKIPPED Build Number: ${CODEBUILD_BUILD_NUMBER} Env: ${ENVIRONMENT}" "warning" "${file_content}"

        log "${file_content}"
    else
        log "File not found: $skippedFile" "warning"
    fi

}

# Function to assume an AWS IAM role and set the new credentials as environment variables
#
# Arguments:
#   $1: The ARN of the target role to assume
#
# Returns:
#   None
function assume_role() {
    acc="$1"
    REPO_NAME="$2"
    PARTITION="$3"
    REGION="$4"

    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN

    log "Setting new creds..."
    CREDS=$(aws sts assume-role \
                        --role-arn "arn:${PARTITION}:iam::${acc}:role/service-role/deployer-impact-$REPO_NAME-role" \
                        --role-session-name "$REPO_NAME-impact" \
                        --region "$REGION")


    AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .Credentials.AccessKeyId)
    AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .Credentials.SecretAccessKey)
    AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .Credentials.SessionToken)

    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN    
    
}




