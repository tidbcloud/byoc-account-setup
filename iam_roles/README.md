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
   bash tidbcloud-byoc-setup.sh <ControlPlaneAccountId> <ClinicAccountId> <TidbHostedZoneId> <O11yHostedZoneId> <TidbPCAArn> [O11yGlobalRoleArn]
   ```
   > Replace `<parameter>` with the value prepared in the previous step