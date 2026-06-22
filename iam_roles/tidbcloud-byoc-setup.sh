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
  --additional-pca-arns <arns>       Comma-separated additional PCA ARNs for multi-region
                                     (full ARNs, e.g. arn:aws:acm-pca:us-east-1:ACCOUNT:certificate-authority/ID)
  --additional-tidb-hz-ids <ids>     Comma-separated additional TiDB hosted zone IDs for multi-region
                                     (e.g. Z111AAA,Z222BBB)
  --additional-o11y-hz-ids <ids>     Comma-separated additional o11y hosted zone IDs for multi-region
                                     (e.g. Z111AAA,Z222BBB)
  --o11y-global-role-arns <arns>     Comma-separated list of O11Y global role ARNs
                                     (default: arn:aws:iam::557537366020:role/globalserver-role-780c8f0,arn:aws:iam::380838443567:role/tidbcloud-global-apigw)
  --github-runner-id <id>            Google account ID for GitHub runner
                                     (default: 114667344163696279999)
  -h, --help                         Show this help message
EOF
  exit "${1:-1}"
}

# Defaults
O11yGlobalRoleArns="arn:aws:iam::557537366020:role/globalserver-role-780c8f0,arn:aws:iam::380838443567:role/tidbcloud-global-apigw"
GithubRunnerGoogleAccountId="114667344163696279999"
ControlPlaneAccountId=""
ClinicAccountId=""
TidbHostedZoneId=""
O11yHostedZoneId=""
TidbPCAArn=""
AdditionalPCAArns=""
AdditionalTidbHostedZoneIds=""
AdditionalO11yHostedZoneIds=""

require_arg() {
  if [[ $# -lt 2 || "${2-}" == -* ]]; then
    echo "Error: $1 requires a value"
    usage
  fi
}

# Convert comma-separated hosted zone IDs to full ARNs
# e.g. "Z111,Z222" -> "arn:aws:route53:::hostedzone/Z111,arn:aws:route53:::hostedzone/Z222"
hz_ids_to_arns() {
  local ids="${1// /}"
  local result=""
  IFS=',' read -ra id_array <<< "$ids"
  for id in "${id_array[@]}"; do
    [[ -n "$result" ]] && result="${result},"
    result="${result}arn:aws:route53:::hostedzone/${id}"
  done
  echo "$result"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-id)
      require_arg "$@"
      ControlPlaneAccountId="$2"; shift 2 ;;
    --clinic-id)
      require_arg "$@"
      ClinicAccountId="$2"; shift 2 ;;
    --tidb-hz-id)
      require_arg "$@"
      TidbHostedZoneId="$2"; shift 2 ;;
    --o11y-hz-id)
      require_arg "$@"
      O11yHostedZoneId="$2"; shift 2 ;;
    --pca-arn)
      require_arg "$@"
      TidbPCAArn="$2"; shift 2 ;;
    --additional-pca-arns)
      require_arg "$@"
      AdditionalPCAArns="${2// /}"; shift 2 ;;
    --additional-tidb-hz-ids)
      require_arg "$@"
      AdditionalTidbHostedZoneIds="${2// /}"; shift 2 ;;
    --additional-o11y-hz-ids)
      require_arg "$@"
      AdditionalO11yHostedZoneIds="${2// /}"; shift 2 ;;
    --o11y-global-role-arns)
      require_arg "$@"
      O11yGlobalRoleArns="$2"; shift 2 ;;
    --github-runner-id)
      require_arg "$@"
      GithubRunnerGoogleAccountId="$2"; shift 2 ;;
    -h|--help)
      usage 0 ;;
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

deploy_overrides=""
if [[ -n "$AdditionalO11yHostedZoneIds" ]]; then
  deploy_overrides="AdditionalO11yHostedZoneIds=$(hz_ids_to_arns "$AdditionalO11yHostedZoneIds")"
fi

# shellcheck disable=SC2086
aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-deploy \
  --template-file ./tidbcloud-byoc-setup-deploy.yaml \
  --parameter-overrides ControlPlaneAccountId=$ControlPlaneAccountId \
               GithubRunnerGoogleAccountId=$GithubRunnerGoogleAccountId \
               O11yHostedZoneId=$O11yHostedZoneId \
               $deploy_overrides \
  --capabilities CAPABILITY_NAMED_IAM

dataplane_overrides="ResourceNamePrefix=tidbcloud RequiredManagedByTagValue=PingCAP SLIBucketNamePrefix=tidbcloud-sli-data"
[[ -n "$AdditionalPCAArns" ]] && dataplane_overrides="$dataplane_overrides AdditionalPCAArns=$AdditionalPCAArns"
if [[ -n "$AdditionalTidbHostedZoneIds" ]]; then
  dataplane_overrides="$dataplane_overrides AdditionalHostedZoneIds=$(hz_ids_to_arns "$AdditionalTidbHostedZoneIds")"
fi

# shellcheck disable=SC2086
aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-dataplane \
  --template-file ./tidbcloud-byoc-setup-dataplane.yaml \
  --parameter-overrides ControlPlaneAccountId=$ControlPlaneAccountId \
               HostedZoneId=$TidbHostedZoneId \
               PCAArn=$TidbPCAArn \
               ClinicAccountId=$ClinicAccountId \
               $dataplane_overrides \
  --capabilities CAPABILITY_NAMED_IAM

o11y_overrides=""
if [[ -n "$AdditionalO11yHostedZoneIds" ]]; then
  o11y_overrides="AdditionalO11yHostedZoneIds=$(hz_ids_to_arns "$AdditionalO11yHostedZoneIds")"
fi

# shellcheck disable=SC2086
aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-o11y \
  --template-file ./tidbcloud-byoc-setup-o11y.yaml \
  --parameter-overrides O11yHostedZoneId=$O11yHostedZoneId \
               O11yGlobalRoleArns=$O11yGlobalRoleArns \
               $o11y_overrides \
  --capabilities CAPABILITY_NAMED_IAM
