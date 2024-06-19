# Directory structure

The basic directory structure is same for this template repository and its forked versions
The difference can be in the content of some directories where are specifics for given repository.

* `.rpl`
The only required files are the `buildspec.yml` and `deployspec.yml` but we have created some helper scripts to ease the maintanance and to modularize the code.

* `./rpl/scripts`
Set of scripts that are used to automate the deployment process.

* `./rpl/ami`
Contains the AMI deploy related files. All files are in AWSEnvDeployHub repository

* `./rpl/CFN`
Definition of the RPL S3 bucket which is used by this project. There is possibility to define your own S3 bucket but then all permissions to it must be sort out.

* `./rpl/files/config-template.json`
Template of the configuration file for defining your project. Which must be renamed to `config.json` in your own repository

* `./rpl/files/yq_linux_amd64`
YQ is a lightweight and portable command-line YAML processor. It is used to parse the configuration file in yaml format

* `templates`
Contains templates for building new objects in repository. If you want to deploy CFN so it must be stored here.

* `scripts` 
Contains all scripts which are called from CFN templates

* `examples`
Contains examples of the templates and scripts

* `functions.sh` and `functions_aws.sh` 
definition of all shell functions used in project

* `tests`
testing functions used during development

* `Documentation`
documentation of the project