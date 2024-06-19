# CONFIG FILE KEY DEFINITIONS

| Key | Description | Allowed Values/Example |
| --- | ----------- | --------------------- |
| ORG | The organization for which the pipeline is being set up | Example: "impact" |
| ROLE_TYPE | The role which owns this deployment| Example: "dbsql" |
| PROMOTIONS_BUCKET | The bucket where the build artifacts are stored | Example: "cdc-build-sync-bucket-test" |
| TEMPLATES_FOLDER | The folder where the templates for the deployment are stored | Example: "templates" |
| SCRIPTS_FOLDER | The folder where the scripts for the pipeline are stored | Example: "scripts" |
| SCRIPTS_FULL_UPLOAD | Determines if all scripts should be uploaded | "true" or "false" |
| SLACK_CHANNEL | The Slack channel where notifications are sent | Example: "#notify_dba" |
| SLACK_HOOK | The webhook URL for Slack notifications | Example: "https://hooks.slack.com/services/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" |
| STACKTODELETE | The stacks that should be firstly deleted and then created every time when is done commit to update the stack| Array of stack names |
| MULTISTACK | The template that is deployed many times in one account | Array of template names |
| SCHEDULE | The schedule for different pipeline tasks | Object with task names and types |
| BRANCH | The branches for different environments | Object with branch names, target environments, and environment names |
| ENVIRONMENT | The configuration for different environments | Object with environment names, regions, bucket names, and default accounts |
| ACCOUNT | The configuration for different accounts | Object with account names, environment names, account IDs, and manual stack names |