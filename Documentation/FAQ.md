# Q&A

<details>
<summary><h4>What files have to be copied manually to S3 and where for EC2 deployment?</h4></summary>

1. Location: s3://integration-dbsql-rpl/AWSInstanceDeployHub/
Files:
- SQL2019.zip
- SQL2019_Std.zip
- SQL2019_Dev.zip
- SQL2022.zip
- SQL2022_Std.zip
- SQL2022_Dev.zip
- Tools.zip
- SSMS-Setup-ENU.exe
- /Updates

2. Location: s3://integration-dbsql-rpl/AWSInstanceDeployHub/scripts/vault/
Files:
- vault.exe

3. Location: s3://integration-dbsql-rpl/AWSInstanceDeployHub/scripts/
Files:
- Tools.zip
- SSMS-Setup-ENU.exe
</details>
<details>
<summary><h4>What files have to be copied manually to S3 and where for Solarwinds deployment?</h4></summary>

- Location: s3://integration-dbsql-rpl/AWSInstanceDeployHub/scripts/Solarwinds/installer/
- File: *SolarWinds-DPA-xxxx-64bit.tar.gz* = Installation file which must be download from Solarwinds customer portal
</details>
<details>
<summary><h4>What other repositories have to be zipped and copied to AWSInstanceDeployHub?</h4></summary>

1. [DPA](https://github.concur.com/impact/DPA)
- DPA.zip -> /scripts/DPA/

2. [Concur.SqlBuild](https://github.concur.com/dba/Concur.SqlBuild)
- Concur.SqlBuild.zip -> /scripts/
</details>
<details>
<summary><h4>What is the process for making changes in templates or scripts?</h4></summary>
To make changes in templates or scripts, create a new branch from pre-release, make the changes, and then create a pull request back to pre-release and then to the main branch.
</details>
<details>
<summary><h4>What is the alternative to using the DCP tool?</h4></summary>
If someone is not interested in using the DCP tool, they can manually grab the CFN templates and use AWS Cloudformation. However, this method is not supported.
</details>
<details>
<summary><h4>What tool should be used to build new servers?</h4></summary>
The DCP tool should be used to build new servers.
</details>
<details>
<summary><h4>Where can environment resources like bucket, policies, sns topics be updated?</h4></summary>
Environment resources like bucket, policies, sns topics can be updated at https://github.concur.com/impact/AWSEnvDeployHub.
</details>
<details>
<summary><h4>Where is the stuff that is deployed with RPL solution now stored?</h4></summary>
The stuff that is deployed with RPL solution is now stored to a specific bucket dedicated to only RPL deployments. The bucket is <environment>-dbsql-rpl (<environment> = apj1, eu2, us2, integration, uspsscc).
</details>
<details>
<summary><h4>How can I deploy batch of servers?</h4></summary>

1. Do a change in the template what you want to use for deployment (it can be even space)
2. Edit parameter-value file with same name but with extension .config and add there values for the template custom parameters in JSON format
3. Set parameters "Action":"Deploy",  "Account" which is one of the existing accounts in given environment and "BucketName":"<env>-dbsql-rpl"
4. Full JSON example for one server definition. In this example is stack name `TestSQLDCP91`
 ```json
  "integration":{
    "TestSQLDCP91":{
    "Parameters":{
      "Account":"integration-tools",
      "Action":"Deploy",
      "DiskSizeOfGDrive":"100",
      "DiskSizeOfDDrive":"100",
      "RoleType":"dbsql",
      "NameOfCRecordForServer":"toolssql91",
      "DiskSizeOfEDrive":"100",
      "DiskSizeOfMDrive":"100",
      "BucketName":"integration-dbsql-rpl",
      "SQLVersion":"SQL2019_Dev",
      "Environment":"INTEGRATION",
      "AZ":"zoneA",
      "InstanceType":"r5.xlarge",
      "ConfigType":"TESTING-ALL",
      "DiskSizeOfFDrive":"100",
      "NameOfCRecordsAdditional":"none"
    }
    }
  },
 ```
</details>
<details>
<summary><h4>What is for the parameters 'Account' and 'Action' or 'BucketName'?</h4></summary>

- **Account** = the list of the aws account where can be the template deployed via RPL. If the CFN template is build manually so this parameter can be ignored
- **Action** = list of the action which can be/are done with the CFN template
    - *S3Bucket* = template is stored to S3Bucket after each PR
    - *Deploy* = template can be directly deployed via RPL (it has to have set this parameter in parameter-value config file)
    - *ScheduleDeploy* = template can be deployed via RPL and called from EvenBridge, not PR is need but there must be set EventBridge rule in CodeBuild account + it has to have set 
- **BucketName** = bucket dedicated to only RPL deployments. The bucket is <environment>-dbsql-rpl (<environment> = apj1, eu2, us2, integration, uspsscc).
- *note: The rest of parameters are standard for CFN instance deployment*
</details>
