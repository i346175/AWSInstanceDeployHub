# mssql-scripts
```
Date        Ticket#     Description
3/14/2022   CSCI-2879   Modified Function [Generate-RandomPassword] to store the sa password temporarily in a file
8/17/2022   CSCI-4153   [Domainless] Change SQL INSTANCEDIR to E drive
1/13/2023   CSCI-5300   Proxy fix in template & mssqlscript files to resolve Fortiguard issue
1/17/2023   CSCI-5311   Update mssql-scripts/mssql_artifact_downloader.ps1 to use DEV bits for INTEGRATION builds
1/19/2023   CAM-2238    Removed "add_hostname_microservice_tag.ps1" from being hard-coded into CFTemplate, and moved to CFTemplateScripts directory.
1/24/2023   CSCI-5338   Create EC2 Tag "IsDomainAttached" to identify if that the server is domain attached
1/24/2023   CSCI-5339   Update domain templates to use include SQL2019 Standard Edition
2/3/2023    CAM-2302    Fix WinRM errors via creating a PSSession in post-build scripts
4/24/2023   CAM-1757    Created 2 Node template. Moved some scripts from hard-coded to the CFTemplateScripts directory.
5/2/2023    CSCI-5898   Adding EC2 tag CNameList
6/1/2023    CSCI-6008   Added Restart-Computer in mssql-scripts/CFTemplateScripts/WKS_Tools_Install.ps1
6/20/2023   CSCI-6056   Code update to NOT INCLUDE the DUMMY CName in the CNameList EC2 tag
7/3/2023    CSCI-6103   1. Moved StorageConfig task script from CFN template to CFTemplateScripts folder
                        2. Adding NVMe storage config task for F-drive under storage_config.ps1
                        3. Add scheduler task to map NVMe volume as F-drive
7/5/2023    CSCI-6128   Bug fix for changes made under CSCI-6056
7/19/2023   CSCI-6142   Condition to allow ENT and STD addition builds in INTEGRATION
8/29/2023   CSCI-6333   SKIP Validation to check for latest AMI
9/19/2023   CAM-2727    Bug Fix for additional cnames and timeout issue for ClusterCreationWaitCondition in 2-node
11/16/2023  CSCI-6550   Update SystemDB location to C drive in sql2019InstallConfigFile_DomainLess.ini
11/22/2023  CSCI-4017   1. Moved install_NewRelic task from CFN templates into CFTemplateScripts; 
                        2. Added NewRelic Flex Configuration
12/1/2023   CSCI-6476   Add script to configure system page file
1/26/2024   CSCI-6701   Add CloudWatch Installation script and call in build templates (Scope: US2, EU2 and APJ1)
1/29/2024   CSCI-6702   Moved WKS task scripts from CFN template to CFTemplateScripts folder
2/2/2024    CSCI-6705   Remove dbsql_admins from sysadmin server role
2/5/2024    CSCI-6693   Added Configurations for SQL2022 builds
2/7/2024    CSCI-6747   Create Backup Directories as part of Server Provisioning
2/7/2024    CSCI-6750   [BUG] Fix add_to_domain task failures
2/8/2024    CSCI-6764   [BUG] [PS Monitor - Sync Logins] script fix to add TrustServerCertificate switch for SQL connect
2/8/2024    CSCI-6768   Modified HasNVME condition to always return FALSE to not use Local NVME for tempdb
3/15/2024   CSCI-6893   Updated CFN templates to use baked AMI SSM parameter references

```

```
