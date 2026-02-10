# TiDB Cloud Byoc Account Initialization

This setup script will use AWS cloudformation to initialize your BYOC cloud account, creating necessary IAM roles and their corresponding policies.

## Prerequisites

Before you begin, ensure you have the following:

1. **AWS CLI Configured**
   * Your AWS CLI must be configured with appropriate credentials and permissions for your AWS account.
   * Necessary permissions include actions for IAM and CloudFormation.

2. **Hosted Zones**
   * You need to configure two public hosted zones in advance: one for TiDB and one for O11Y.
   * AWS document for creating pubic hosted zones: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingHostedZone.html

3. **Private CA**
   * You need to configure a private CA before running this script
   * AWS document for creating a private CA: https://docs.aws.amazon.com/privateca/latest/userguide/create-CA.html

## Initialization


1. **Parameters**

   `tidbcloud-byoc-setup.sh` requires 5 mandatory parameters:

   * `ControlPlaneAccountId`: The AWS account of TiDB Cloud control plane, you can get it from PingCAP
   * `ClinicAccountId`: The AWS account of clinic service, you can get it from PingCAP
   * `TidbHostedZoneId`: The id of the hosted zone for TiDB, obtained in `prerequisites` step
   * `O11yHostedZoneId`: The id of the hosted zone for O11Y, obtained in `prerequisites` step
   * `TidbPCAArn`: Arn of the private CA you prepared in `prerequisites` step

2. **Run Script**

   ```bash
   bash tidbcloud-byoc-setup.sh <ControlPlaneAccountId> <ClinicAccountId> <TidbHostedZoneId> <O11yHostedZoneId> <TidbPCAArn> [O11yGlobalRoleArns]
   ```
   > Replace `<parameter>` with the value prepared in the previous step
   > `O11yGlobalRoleArns` is optional and defaults to "arn:aws:iam::557537366020:role/globalserver-role-780c8f0,arn:aws:iam::380838443567:role/tidbcloud-global-apigw" (comma-separated list of role ARNs)

## Update

   If you need to update existing CloudFormation stacks (e.g. after modifying the YAML templates), simply re-run `tidbcloud-byoc-setup.sh` with the same parameters:

   ```bash
   bash tidbcloud-byoc-setup.sh <ControlPlaneAccountId> <ClinicAccountId> <TidbHostedZoneId> <O11yHostedZoneId> <TidbPCAArn> [O11yGlobalRoleArns]
   ```

   > `aws cloudformation deploy` is idempotent — it will create a stack if it does not exist, or update it if it already exists. If there are no changes, the command will exit with no-op.
