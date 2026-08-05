# TiDB Cloud Byoc Account Initialization

This setup script will use AWS cloudformation to initialize your BYOC cloud account, creating necessary IAM roles and their corresponding policies.

## Prerequisites

Before you begin, ensure you have the following:

1. **AWS CLI Configured**
   * Your AWS CLI must be configured with appropriate credentials and permissions for your AWS account.
   * The AWS principal that runs this script must be allowed to deploy CloudFormation stacks that create named IAM resources.
   * For quick setup, you can attach the following AWS managed policies to the principal running the script:
     * `AWSCloudFormationFullAccess`
     * `IAMFullAccess`
   * For stricter environments, see [Least-privilege permissions](#least-privilege-permissions).

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

   Image delivery is also configurable:

   | Parameter | Description |
   |-----------|-------------|
   | `--image-delivery-mode` | Image delivery mode, either `push` or `pull`. Defaults to `push`. |

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

### Image delivery modes

The `auto-deploy-sync-image` role supports one image delivery mode at a time:

- `push` (default): PingCAP's Google OIDC GitHub runner assumes the role and pushes images into customer ECR repositories tagged with `ManagedBy=PingCAP`. This preserves the existing behavior.
- `pull`: customer EC2 assumes the role through the `auto-deploy-sync-image` instance profile. The instance can pull approved images from the PingCAP DBAAS (`380838443567`) and observability (`557537366020`) ECR accounts in `us-west-2`, then copy them into ECR repositories in any region of the customer account.

To select pull mode during initialization, add the mode flag to the normal setup command:

```bash
bash tidbcloud-byoc-setup.sh \
    --image-delivery-mode pull \
    --control-plane-id <ControlPlaneAccountId> \
    --clinic-id <ClinicAccountId> \
    --tidb-hz-id <TidbHostedZoneId> \
    --o11y-hz-id <O11yHostedZoneId> \
    --pca-arn <TidbPCAArn>
```

Pull mode also requires PingCAP to grant repository-level pull access to the following customer principal:

```text
arn:aws:iam::<ACCOUNT_ID>:role/auto-deploy-sync-image
```

Contact PingCAP to configure the required repository-level pull access. The AWS principal that launches or updates the customer EC2 instance must also be allowed to pass `auto-deploy-sync-image` to EC2.

## Update

If you need to update existing CloudFormation stacks (e.g. after modifying the YAML templates), use `tidbcloud-byoc-update.sh`. It automatically fetches existing parameters from deployed stacks, so you don't need to pass them again for those parameters.

> Note: The script only reuses parameters that already exist in the stack. If the template introduces a new parameter without a default value, you must still provide that value when updating or the update will fail.

Update a specific stack:

```bash
bash tidbcloud-byoc-update.sh --stack deploy
```

Enable Route 53 permissions for external-dns on the existing EKS node role:

```bash
bash tidbcloud-byoc-update.sh \
    --stack dataplane \
    --enable-external-dns-node-role-policy true
```

Update all stacks:

```bash
bash tidbcloud-byoc-update.sh --stack all
```

> `--stack` must be one of `deploy`, `dataplane`, `o11y`, or `all`
> The script requires that the stack has already been created via `tidbcloud-byoc-setup.sh`

### Changing image delivery mode

Switch an existing deployment to customer pull mode:

```bash
bash tidbcloud-byoc-update.sh \
    --stack deploy \
    --image-delivery-mode pull
```

This replaces the role's Google OIDC trust and push policy with the EC2 trust and pull policy, and creates the `auto-deploy-sync-image` instance profile.

Switch back to PingCAP push mode:

```bash
bash tidbcloud-byoc-update.sh \
    --stack deploy \
    --image-delivery-mode push
```

This restores the Google OIDC trust and tag-constrained push policy and removes the pull-mode instance profile. The `auto-deploy-sync-image` role itself is retained in both directions.

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

## Least-privilege permissions

For environments that cannot use the AWS managed policies listed above, attach a policy like the following to the AWS principal running `tidbcloud-byoc-setup.sh`. Replace `<ACCOUNT_ID>` with your AWS account ID.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudFormationDeploy",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateChangeSet",
        "cloudformation:DescribeChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DeleteChangeSet",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResource",
        "cloudformation:DescribeStackResources",
        "cloudformation:GetTemplate",
        "cloudformation:GetTemplateSummary",
        "cloudformation:ValidateTemplate",
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "cloudformation:ListChangeSets",
        "cloudformation:ListStacks"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageTiDBCloudIAMRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:role/auto-deploy-sync-image",
        "arn:aws:iam::<ACCOUNT_ID>:role/auto-deploy-cli",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-eks-service-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-eks-node-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-audit-log-write-only-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-dataplane-manager-assumed-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-sli-assumed-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-sli-firehose-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-control-plane-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-agent-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-eks-cluster-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-eks-node-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-apigw-role"
      ]
    },
    {
      "Sid": "PassTiDBCloudRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-eks-node-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-eks-service-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-eks-node-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-eks-cluster-role"
      ]
    },
    {
      "Sid": "ManageTiDBCloudInstanceProfile",
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:instance-profile/tidbcloud-eks-node-instance-profile",
        "arn:aws:iam::<ACCOUNT_ID>:instance-profile/auto-deploy-sync-image"
      ]
    }
  ]
}
```
