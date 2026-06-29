# TiDB Cloud Byoc Account Initialization

This setup script will use AWS cloudformation to initialize your BYOC cloud account, creating necessary IAM roles and their corresponding policies.

## Prerequisites

Before you begin, ensure you have the following:

1. **AWS CLI Configured**
   * Your AWS CLI must be configured with appropriate credentials and permissions for your AWS account.
   * Necessary permissions include actions for IAM and CloudFormation.

2. **Hosted Zones**
   * You need to configure two public hosted zones in advance: one for TiDB and one for O11Y.
   * For multi-region deployments, the same hosted zones can be shared across all regions, or you can create dedicated hosted zones per region.
   * AWS document for creating public hosted zones: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingHostedZone.html

3. **Private CA**
   * You need to configure a private CA before running this script.
   * For multi-region deployments, the same PCA can be shared across all regions, or you can create a dedicated PCA per region.
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

   Optional parameters for multi-region deployments (all three are optional; omit any that are shared with the primary region):

   | Parameter | Description |
   |-----------|-------------|
   | `--additional-pca-arns` | Comma-separated ARNs of additional PCAs for extra regions. Omit if all regions share the same PCA specified by `--pca-arn`. (e.g. `arn:aws:acm-pca:us-east-1:ACCOUNT:certificate-authority/ID`) |
   | `--additional-tidb-hz-ids` | Comma-separated IDs of additional TiDB hosted zones for extra regions. Omit if all regions share the same hosted zone specified by `--tidb-hz-id`. (e.g. `Z111AAA,Z222BBB`) |
   | `--additional-o11y-hz-ids` | Comma-separated IDs of additional O11Y hosted zones for extra regions. Omit if all regions share the same hosted zone specified by `--o11y-hz-id`. (e.g. `Z111AAA,Z222BBB`) |

2. **Run Script**

   Single-region:
   ```bash
   bash tidbcloud-byoc-setup.sh \
       --control-plane-id <ControlPlaneAccountId> \
       --clinic-id <ClinicAccountId> \
       --tidb-hz-id <TidbHostedZoneId> \
       --o11y-hz-id <O11yHostedZoneId> \
       --pca-arn <TidbPCAArn>
   ```

   Multi-region with shared resources (same PCA and hosted zones for all regions):
   ```bash
   bash tidbcloud-byoc-setup.sh \
       --control-plane-id <ControlPlaneAccountId> \
       --clinic-id <ClinicAccountId> \
       --tidb-hz-id <TidbHostedZoneId> \
       --o11y-hz-id <O11yHostedZoneId> \
       --pca-arn <TidbPCAArn>
   ```

   Multi-region with dedicated resources per region:
   ```bash
   bash tidbcloud-byoc-setup.sh \
       --control-plane-id <ControlPlaneAccountId> \
       --clinic-id <ClinicAccountId> \
       --tidb-hz-id <Region1TidbHostedZoneId> \
       --o11y-hz-id <Region1O11yHostedZoneId> \
       --pca-arn <Region1PCAArn> \
       --additional-pca-arns <Region2PCAArn>,<Region3PCAArn> \
       --additional-tidb-hz-ids <Region2TidbHZId>,<Region3TidbHZId> \
       --additional-o11y-hz-ids <Region2O11yHZId>,<Region3O11yHZId>
   ```

   You can also mix shared and dedicated resources — for example, share the PCA across regions but use separate hosted zones:
   ```bash
   bash tidbcloud-byoc-setup.sh \
       --control-plane-id <ControlPlaneAccountId> \
       --clinic-id <ClinicAccountId> \
       --tidb-hz-id <Region1TidbHostedZoneId> \
       --o11y-hz-id <Region1O11yHostedZoneId> \
       --pca-arn <SharedPCAArn> \
       --additional-tidb-hz-ids <Region2TidbHZId>,<Region3TidbHZId> \
       --additional-o11y-hz-ids <Region2O11yHZId>,<Region3O11yHZId>
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

### Adding multi-region support to an existing deployment

Existing single-region deployments can be extended to cover additional regions without re-creating any IAM roles. The new multi-region parameters default to empty, so a plain `--stack all` update is safe and causes no functional change.

If the new region can share the same PCA and hosted zones already in use, no additional parameters are needed — the existing resources will cover all regions automatically.

To enable an additional region with its own dedicated resources, pass those resources when updating:

```bash
bash tidbcloud-byoc-update.sh --stack all \
    --additional-pca-arns <Region2PCAArn> \
    --additional-tidb-hz-ids <Region2TidbHZId> \
    --additional-o11y-hz-ids <Region2O11yHZId>
```

Each flag is independent — omit any that should remain shared with the primary region. For example, to add a region with its own hosted zones but share the existing PCA:

```bash
bash tidbcloud-byoc-update.sh --stack all \
    --additional-tidb-hz-ids <Region2TidbHZId> \
    --additional-o11y-hz-ids <Region2O11yHZId>
```

For three or more regions with dedicated resources, pass all values as comma-separated lists:

```bash
bash tidbcloud-byoc-update.sh --stack all \
    --additional-pca-arns <Region2PCAArn>,<Region3PCAArn> \
    --additional-tidb-hz-ids <Region2TidbHZId>,<Region3TidbHZId> \
    --additional-o11y-hz-ids <Region2O11yHZId>,<Region3O11yHZId>
```

Once provided, these values are stored in the CloudFormation stack and replayed automatically on future updates.
