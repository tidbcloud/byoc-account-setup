# PingCAP AWS Conf Security Scan Tool Deployment Guide (deploy_prebuilt.sh)

This guide explains how to deploy and run awsconfcheck using prebuilt binaries with `deploy_prebuilt.sh` (no local Go toolchain required).

## What this script does
- Detects existing prebuilt binaries for linux/amd64 and/or linux/arm64.
- Packages each available architecture into a Lambda zip (adds a `bootstrap`).
- Creates or reuses a managed S3 bucket (tagged, with a marker object) and uploads the zips.
- Deploys/updates the CloudFormation stack that provisions the Lambda functions (amd64 and/or arm64).
- Optionally invokes the function once (single-run) and prints the S3 location of the HTML report.

## What this tool checks (built-in)
These are the checks currently implemented and shown in the HTML/JSON report. Some are global (account-wide), others are evaluated per-region or per-resource.

- Account
  - Security contact information should be provided for an AWS account
- IAM password policy (account-level)
  - Requires minimum password length of 14 or greater
  - Requires at least one uppercase letter
  - Requires at least one lowercase letter
  - Requires at least one symbol
  - Requires at least one number
- S3
  - General purpose buckets should have Block Public Access settings enabled (evaluated per bucket)
- CloudTrail
  - A multi-Region trail is enabled and includes read and write management events
- GuardDuty Runtime Monitoring
  - GuardDuty Runtime Monitoring should be enabled (overall)
  - GuardDuty EC2 Runtime Monitoring should be enabled
  - GuardDuty EKS Runtime Monitoring should be enabled
  - GuardDuty ECS Runtime Monitoring should be enabled
- Amazon Inspector (Inspector2)
  - Amazon Inspector EC2 scanning should be enabled
  - Amazon Inspector ECR scanning should be enabled
  - Amazon Inspector Lambda code scanning should be enabled
  - Amazon Inspector Lambda standard scanning should be enabled
- EBS (EC2)
  - Attached EBS volumes should be encrypted at-rest
- Macie
  - Macie should be enabled

Notes:
- Results are labeled PASS/FAIL/UNKNOWN with categorized reasons (e.g., NOT_CONFIGURED, PERMISSION_DENIED).
- Some S3 results are per-bucket; global scope/region “global” may appear for control-plane APIs.

## Recommended commands
Quick, copy-pasteable examples for common workflows. Prefer using an SSO profile (set up via `aws configure sso`) and pass it with `--profile`.

- Interactive deploy with prompts (SSO profile):
```bash
bash deploy_prebuilt.sh --profile my-sso
```

- Non-interactive deploy scanning all authorized regions, auto-choose arch, and tail logs (SSO profile):
```bash
bash deploy_prebuilt.sh \
  --profile my-sso \
  --region us-east-1 \
  --stack-name prebuilt-scan \
  --regions all \
  --concurrency 15 \
  --log-tail
```

- Deploy to a subset of regions and use an existing bucket name (SSO profile):
```bash
bash deploy_prebuilt.sh \
  --profile my-sso \
  --region us-east-1 \
  --stack-name prebuilt-scan \
  --regions us-east-1,us-west-2,ap-southeast-1 \
  --bucket-name my-security-reports
```

<!-- Cross-account assume-role example removed (flags soft-deprecated & hidden from --help). -->

- Force architecture on invoke (when both are packaged; SSO profile):
```bash
bash deploy_prebuilt.sh --profile my-sso --region us-east-1 --stack-name prebuilt-scan --arch arm64
```

- Run IAM simulate precheck only (no deploy; SSO profile):
```bash
bash deploy_prebuilt.sh --profile my-sso --region us-east-1 --precheck
```

- CloudFormation lifecycle precheck only (SSO profile):
```bash
bash deploy_prebuilt.sh --profile my-sso --region us-east-1 --precheck-cfn
```

- Bulk cleanup (list and selectively delete managed stacks/functions/buckets; SSO profile):
```bash
bash deploy_prebuilt.sh --profile my-sso --region us-east-1 --cleanup
```

- Generate a presigned URL for the latest HTML report (replace with actual values from script output; SSO profile):
```bash
aws s3 presign s3://<bucket>/reports/<stack>/<file>.html --expires-in 3600 --profile my-sso
```

## Prerequisites
- AWS CLI v2 configured (optionally with a named profile)
- jq, zip, curl
- An SSO or long-term credential that can deploy CloudFormation, Lambda, IAM, and S3 resources
- Prebuilt binaries present in a directory

SSO quick setup
```bash
# One-time configuration to create an SSO profile
aws configure sso

# Login each session and pass the profile to the script/CLI
aws sso login --profile my-sso

# Option A: pass profile flag
bash deploy_prebuilt.sh --profile my-sso

# Option B: export as default for the shell session
export AWS_PROFILE=my-sso
bash deploy_prebuilt.sh
```

## Step-by-step tutorial
Follow these steps end-to-end. If you prefer a quick glance, see Quick start and Typical usage below.

1) Prepare a workspace and AWS auth

```bash
# Option A: Use an AWS profile with long-term keys (already configured via `aws configure`)
export AWS_PROFILE=my-profile

# Option B: Use AWS SSO (IAM Identity Center)
aws configure sso             # one-time profile setup
aws sso login --profile my-sso
export AWS_PROFILE=my-sso
```

2) Deploy (choose interactive or non-interactive)

Interactive (guided prompts):
```bash
bash deploy_prebuilt.sh
```

Non-interactive (example across all authorized regions):
```bash
bash deploy_prebuilt.sh \
  --region us-east-1 \
  --stack-name prebuilt-scan \
  --regions all \
  --concurrency 15 \
  --log-tail
```

If you omit `--binary-dir`, the script looks for binaries in `./dist`.

Notes:
- Missing architectures are auto-disabled; you may deploy only arm64 or only amd64 as needed.

3) Verify the run and open the HTML report

The script prints both the S3 path and a private HTTPS URL. You can also generate a presigned link:
```bash
# Replace with values printed by the script
aws s3 presign s3://<bucket>/<reports-prefix>/<stack>/<file>.html --expires-in 3600
```
Or download locally and open:
```bash
aws s3 cp s3://<bucket>/<reports-prefix>/<stack>/<file>.html ./report.html
open ./report.html   # macOS
```

Success criteria checklist:
- A CloudFormation stack named like your `--stack-name` exists and completes CREATE/UPDATE successfully.
- The Lambda invocation returns a JSON line with a report S3 key.
- The HTML report loads and shows results; filters and theme toggle work.

4) Cleanup when done

Bulk cleanup (list and selectively delete stacks/functions/tagged buckets):
```bash
bash deploy_prebuilt.sh --region us-east-1 --cleanup
```

If you encounter issues, see Required AWS permissions and Troubleshooting below.

## Required AWS permissions
The deploy credentials (profile used to run this script) need permissions to create/update the CloudFormation stack, Lambda functions, supporting IAM roles/policies, write reports to S3, and (optionally) read CloudWatch Logs.

Permissions summary (scope down where possible):
- sts: GetCallerIdentity
- CloudFormation (stack lifecycle): CreateStack, UpdateStack, DeleteStack, DescribeStacks
- Lambda (function lifecycle): CreateFunction, UpdateFunctionCode, UpdateFunctionConfiguration, DeleteFunction, GetFunction
- IAM (to create/update the Lambda execution role and policies): PassRole, CreateRole, DeleteRole, AttachRolePolicy, DetachRolePolicy, PutRolePolicy, DeleteRolePolicy, GetRole
- S3 (managed code/report bucket): CreateBucket, DeleteBucket, PutBucketTagging, GetBucketTagging, ListBucket, GetBucketLocation, PutObject, DeleteObject
- CloudWatch Logs (optional, for `--log-tail`): logs:DescribeLogGroups, logs:DescribeLogStreams, logs:FilterLogEvents
- Optional for precheck: iam:SimulatePrincipalPolicy

### Sample IAM policy (deploy credentials)
Minimal example to attach to the user/role used to run this script. Scope resources to your accounts/regions/buckets where possible.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StsIdentity",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudFormationStackLifecycle",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:GetTemplate",
        "cloudformation:ValidateTemplate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaFunctionLifecycle",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:DeleteFunction",
        "lambda:GetFunction"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IamForLambdaRoleMgmt",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:PassRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3ManagedBucketsAndObjects",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LogsReadForTailing",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "OptionalIamSimulationForPrecheck",
      "Effect": "Allow",
      "Action": [
        "iam:SimulatePrincipalPolicy"
      ],
      "Resource": "*"
    }
  ]
}
```


## Quick start (interactive)
Run with no args and follow prompts:

```bash
bash deploy_prebuilt.sh
```

## Typical non-interactive usage
```bash
bash deploy_prebuilt.sh \
  --region us-east-1 \
  --binary-dir ./prebuilt \
  --stack-name prebuilt-scan \
  --regions all \
  --concurrency 15 \
  --log-tail
```

Result:
- HTML report uploaded to `s3://<bucket>/reports/<stack-name>/<timestamp>-report-<ts>.html`
- The script prints both the S3 path and the private HTTPS URL.

## Common flags
Core
- `--region <region>`: required deploy region
- `--stack-name <name>`: default `awsconfcheck-<timestamp>`
- `--bucket-name <name>`: reuse an existing bucket
- `--random-bucket`: force random-suffix bucket naming
- `--arch <amd64|arm64|auto>`: which architecture to invoke if both packaged (default auto)
- `--binary-dir <dir>`: where your prebuilt binaries are (default: ./dist under current directory)

Runtime / scan
- `--regions <list|all>`: regions to scan (comma-separated or `all`)
- `--concurrency <n>`: worker count (default 10)
- `--authorized-regions-only`: skip regions where access seems denied
- `--loop`: keep runtime loop (disable single-run)
- `--no-invoke`: deploy but do not invoke
- `--log-tail`: tail logs for 30 seconds after invoke

Validation
- `--precheck`: IAM simulate permission precheck only (no deploy)
- `--precheck-cfn`: live CloudFormation create/update/delete precheck only

General
- `--profile <profile>`: AWS CLI profile to use
- `--yes` / `--force`: assume yes for prompts
- `--debug`: verbose shell tracing
- `--cleanup`: interactive cleanup of stacks, functions, and tagged buckets

## Architecture handling
- You may provide one or both architectures; absent ones are automatically disabled.
- When both are packaged, `--arch auto` chooses arm64 by default (falls back to amd64 if arm64 missing).
- The stack deploys functions for each enabled architecture; invocation picks the arch according to `--arch`.

## Buckets, tags, and safety
- Managed buckets are tagged: `ManagedBy=awsconfcheck`, `Stack=<stack-name>`.
- A marker object `.awsconfcheck-marker` is placed to identify provenance.
- On delete you can choose to remove all objects and the bucket, only report objects under `reports/`, or keep everything.

## Outputs and HTML report
- The Lambda returns a JSON line to stdout; the script captures it and prints the report location.
- The HTML report has columns: Check ID, Title, Region/Service, Status, Category, Duration.
- The legacy “API” column and “API & Evidence” section were removed; Print button removed; theme toggle fixed (dark/light).

## Prechecks (recommended)
- `--precheck`: verifies credentials and simulates critical actions when permitted.
- `--precheck-cfn`: performs a real create→update→delete lifecycle with a minimal stack.

## Troubleshooting
- “No prebuilt awsconfcheck binaries found”: ensure the files exist in `--binary-dir` and are executable.
- AccessDenied during deploy: run `--precheck` first; ensure your profile can use CloudFormation/Lambda/IAM/S3.
- Invocation returns `no_status_json`: open CloudWatch logs (`--log-tail`) to diagnose runtime output.

## Cleanup
Use cleanup mode or manually delete the CloudFormation stack via AWS Console / CLI if full removal is desired.

### Bulk cleanup mode
List and selectively delete awsconfcheck resources in the account:

```bash
# Lists stacks (awsconfcheck-*), Lambda functions (awsconfcheck-*), and S3 buckets
# tagged ManagedBy=awsconfcheck, then lets you delete one, many (*), or quit.
bash deploy_prebuilt.sh --region us-east-1 --cleanup
```

Notes:
- Buckets are only eligible if they have tag `ManagedBy=awsconfcheck`.
- Deleting a bucket first removes all objects, then deletes the bucket.
- Use `--yes` to skip interactive confirmations (non-destructive listing still occurs).
- Previously available --delete / --retain-bucket flags were removed in favor of unified --cleanup.
