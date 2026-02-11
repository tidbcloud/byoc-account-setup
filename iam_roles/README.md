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

   `tidbcloud-byoc-setup.sh` requires the following parameters:

   | Parameter | Description |
   |-----------|-------------|
   | `--control-plane-id` | The AWS account of TiDB Cloud control plane, you can get it from PingCAP |
   | `--clinic-id` | The AWS account of clinic service, you can get it from PingCAP |
   | `--tidb-hz-id` | The id of the hosted zone for TiDB, obtained in `prerequisites` step |
   | `--o11y-hz-id` | The id of the hosted zone for O11Y, obtained in `prerequisites` step |
   | `--pca-arn` | ARN of the private CA you prepared in `prerequisites` step |

2. **Run Script**

   ```bash
   bash tidbcloud-byoc-setup.sh \
       --control-plane-id <ControlPlaneAccountId> \
       --clinic-id <ClinicAccountId> \
       --tidb-hz-id <TidbHostedZoneId> \
       --o11y-hz-id <O11yHostedZoneId> \
       --pca-arn <TidbPCAArn>
   ```
   > Replace `<parameter>` with the value prepared in the previous step

## Update

If you need to update existing CloudFormation stacks (e.g. after modifying the YAML templates), use `tidbcloud-byoc-update.sh`. It automatically fetches existing parameters from deployed stacks, so you don't need to pass them again for those parameters.

> Note: The script only reuses parameters that already exist in the stack. If the template introduces a new parameter without a default value, you must still provide that value when updating or the update will fail.

Update a specific stack:

```bash
bash tidbcloud-byoc-update.sh --stack deploy
```

Update all stacks:

```bash
bash tidbcloud-byoc-update.sh --stack all
```

> `--stack` must be one of `deploy`, `dataplane`, `o11y`, or `all`
> The script requires that the stack has already been created via `tidbcloud-byoc-setup.sh`
