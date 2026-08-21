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
   | `--github-runner-id` | Google account ID for the GitHub runner used by BYOC image sync. It is not used for region deployment. |

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

### Auto-deploy managed policies

The deploy stack attaches six customer-managed policies to `auto-deploy-cli` instead of maintaining its permissions in one inline policy. This avoids the IAM inline-policy size limit while preserving the role's existing permissions. The policies are created before CloudFormation updates the role to reference them, so existing deployments can use the normal command:

```bash
bash tidbcloud-byoc-update.sh --stack deploy
```

The managed policy names are `auto-deploy-cli-iam`, `auto-deploy-cli-compute`, `auto-deploy-cli-storage`, `auto-deploy-cli-network`, `auto-deploy-cli-monitoring`, and `auto-deploy-cli-kms`.

#### Policy division principles

When adding a permission, select the policy by the AWS service family that owns the action:

| Policy | Responsibility | Examples |
|---|---|---|
| `auto-deploy-cli-iam` | Identity and role management | IAM, OIDC, service-linked roles |
| `auto-deploy-cli-compute` | Infrastructure provisioning and compute | CloudFormation, EC2, Auto Scaling, EKS, ELB |
| `auto-deploy-cli-storage` | Storage and data delivery | S3, Glue, Firehose |
| `auto-deploy-cli-network` | Network, DNS, and edge services | Route 53 and recovery services, VPC endpoints, API Gateway, ACM, WAF |
| `auto-deploy-cli-monitoring` | Monitoring and log delivery | CloudWatch, CloudWatch Logs |
| `auto-deploy-cli-kms` | Key management | KMS |

Select the policy from the action prefix. If a statement includes actions from unrelated service families, split it into separate statements and place each statement with its service family. Do not use a catch-all policy for unrelated permissions.

#### Quotas that bound this layout

Two IAM quotas apply, and the split trades one for the other:

| Quota | Limit | Current usage |
|---|---|---|
| Managed policy document size | 6,144 characters per policy | six policies, largest around 60% full |
| Managed policies attached to a role | 10 by default, 20 maximum | 6 of 10 slots on `auto-deploy-cli` |

Splitting a policy relieves the size limit but consumes an attachment slot, so prefer adding a permission to the service family that already owns it over creating a seventh policy. Only add a policy once `validate_iam_policy_sizes.py` reports that an existing one is out of room, and note that going past 10 attached policies requires a Service Quotas increase in every customer account — a customer-visible prerequisite, not just a template change.

#### Checking policy sizes

`validate_iam_policy_sizes.py` measures every inline and customer-managed policy against these limits. With no arguments it inspects every template in this directory:

```bash
python iam_roles/validate_iam_policy_sizes.py
```

Pass `--parameter NAME=VALUE` to measure a parameter that grows a policy, such as a multi-region deployment:

```bash
python iam_roles/validate_iam_policy_sizes.py --parameter 'AdditionalO11yHostedZoneIds=arn:aws:route53:::hostedzone/Z111AAA'
```

The inline-policy limit is a 10,240-character budget shared by all of a role's inline policies, so the checker reports the aggregate per role rather than per policy. CI runs these checks on every change under `iam_roles/`.

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

`iam:AttachRolePolicy` and `iam:DetachRolePolicy` are kept in their own statement so that the `iam:PolicyARN` condition constrains which policies may be attached. The condition key is absent from the other IAM calls, so folding these two actions back into a statement that also grants `iam:CreateRole` would deny that statement outright.

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
      "Sid": "AttachTiDBCloudRolePolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy"
      ],
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:role/auto-deploy-cli",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-eks-service-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-eks-node-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-eks-cluster-role",
        "arn:aws:iam::<ACCOUNT_ID>:role/tidbcloud-o11y-eks-node-role"
      ],
      "Condition": {
        "ArnLike": {
          "iam:PolicyARN": [
            "arn:aws:iam::aws:policy/*",
            "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-*"
          ]
        }
      }
    },
    {
      "Sid": "ManageAutoDeployManagedPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:SetDefaultPolicyVersion",
        "iam:ListEntitiesForPolicy"
      ],
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-iam",
        "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-compute",
        "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-storage",
        "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-network",
        "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-monitoring",
        "arn:aws:iam::<ACCOUNT_ID>:policy/auto-deploy-cli-kms"
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
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:instance-profile/tidbcloud-eks-node-instance-profile"
    }
  ]
}
```
