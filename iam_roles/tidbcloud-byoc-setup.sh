#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Required:
  --control-plane-id <id>       The AWS account of TiDB Cloud control plane
  --clinic-id <id>              The AWS account of clinic service
  --tidb-hz-id <id>             The id of the hosted zone for TiDB
  --o11y-hz-id <id>             The id of the hosted zone for O11Y
  --pca-arn <arn>               ARN of the private CA

Optional:
  --o11y-global-role-arns <arns>  Comma-separated list of O11Y global role ARNs
                                  (default: arn:aws:iam::557537366020:role/globalserver-role-780c8f0,arn:aws:iam::380838443567:role/tidbcloud-global-apigw)
  --github-runner-id <id>         Google account ID for GitHub runner
                                  (default: 114667344163696279999)
  -h, --help                      Show this help message
EOF
  exit 1
}

# Defaults
O11yGlobalRoleArns="arn:aws:iam::557537366020:role/globalserver-role-780c8f0,arn:aws:iam::380838443567:role/tidbcloud-global-apigw"
GithubRunnerGoogleAccountId="114667344163696279999"
ControlPlaneAccountId=""
ClinicAccountId=""
TidbHostedZoneId=""
O11yHostedZoneId=""
TidbPCAArn=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-id)
      ControlPlaneAccountId="$2"; shift 2 ;;
    --clinic-id)
      ClinicAccountId="$2"; shift 2 ;;
    --tidb-hz-id)
      TidbHostedZoneId="$2"; shift 2 ;;
    --o11y-hz-id)
      O11yHostedZoneId="$2"; shift 2 ;;
    --pca-arn)
      TidbPCAArn="$2"; shift 2 ;;
    --o11y-global-role-arns)
      O11yGlobalRoleArns="$2"; shift 2 ;;
    --github-runner-id)
      GithubRunnerGoogleAccountId="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Error: unknown option '$1'"
      usage ;;
  esac
done

# Validate required parameters
missing=()
[[ -z "$ControlPlaneAccountId" ]] && missing+=("--control-plane-id")
[[ -z "$ClinicAccountId" ]] && missing+=("--clinic-id")
[[ -z "$TidbHostedZoneId" ]] && missing+=("--tidb-hz-id")
[[ -z "$O11yHostedZoneId" ]] && missing+=("--o11y-hz-id")
[[ -z "$TidbPCAArn" ]] && missing+=("--pca-arn")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing required parameters: ${missing[*]}"
  echo ""
  usage
fi

aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-deploy \
  --template-file ./tidbcloud-byoc-setup-deploy.yaml \
  --parameter-overrides ControlPlaneAccountId=$ControlPlaneAccountId \
               GithubRunnerGoogleAccountId=$GithubRunnerGoogleAccountId \
               O11yHostedZoneId=$O11yHostedZoneId \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-dataplane \
  --template-file ./tidbcloud-byoc-setup-dataplane.yaml \
  --parameter-overrides ControlPlaneAccountId=$ControlPlaneAccountId \
               HostedZoneId=$TidbHostedZoneId \
               PCAArn=$TidbPCAArn \
               ClinicAccountId=$ClinicAccountId \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-o11y \
  --template-file ./tidbcloud-byoc-setup-o11y.yaml \
  --parameter-overrides O11yHostedZoneId=$O11yHostedZoneId \
               O11yGlobalRoleArns=$O11yGlobalRoleArns \
  --capabilities CAPABILITY_NAMED_IAM
