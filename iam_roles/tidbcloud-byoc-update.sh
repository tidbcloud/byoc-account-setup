#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --stack <stack> [OPTIONS]

Required:
  --stack <stack>   The stack to update, one of 'deploy', 'dataplane', 'o11y', or 'all'

Options:
  --additional-pca-arns <arns>       Comma-separated additional PCA ARNs for multi-region
                                     (full ARNs, e.g. arn:aws:acm-pca:us-east-1:ACCOUNT:certificate-authority/ID)
  --additional-tidb-hz-ids <ids>     Comma-separated additional TiDB hosted zone IDs for multi-region
                                     (e.g. Z111AAA,Z222BBB)
  --additional-o11y-hz-ids <ids>     Comma-separated additional o11y hosted zone IDs for multi-region
                                     (e.g. Z111AAA,Z222BBB)
  --enable-external-dns-node-role-policy <true|false>
                                     Whether to enable Route53 permissions for external-dns on EKS node role.
                                     Only applies when updating 'dataplane' or 'all'.
  -h, --help        Show this help message

This script automatically fetches existing parameters from deployed stacks.
No need to pass parameters again unless adding new multi-region resources.
EOF
  exit "${1:-1}"
}

STACK=""
AdditionalPCAArns=""
AdditionalTidbHostedZoneIds=""
AdditionalO11yHostedZoneIds=""
EnableExternalDNSNodeRolePolicy=""

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
    --stack)
      require_arg "$@"
      STACK="$2"; shift 2 ;;
    --additional-pca-arns)
      require_arg "$@"
      AdditionalPCAArns="${2// /}"; shift 2 ;;
    --additional-tidb-hz-ids)
      require_arg "$@"
      AdditionalTidbHostedZoneIds="${2// /}"; shift 2 ;;
    --additional-o11y-hz-ids)
      require_arg "$@"
      AdditionalO11yHostedZoneIds="${2// /}"; shift 2 ;;
    --enable-external-dns-node-role-policy)
      require_arg "$@"
      EnableExternalDNSNodeRolePolicy="$2"; shift 2 ;;
    -h|--help)
      usage 0 ;;
    *)
      echo "Error: unknown option '$1'"
      usage ;;
  esac
done

if [[ -z "$STACK" ]]; then
  echo "Error: missing required parameter: --stack"
  echo ""
  usage
fi

if [[ -n "$EnableExternalDNSNodeRolePolicy" && "$EnableExternalDNSNodeRolePolicy" != "true" && "$EnableExternalDNSNodeRolePolicy" != "false" ]]; then
  echo "Error: --enable-external-dns-node-role-policy must be either 'true' or 'false'"
  exit 1
fi

if [[ -n "$EnableExternalDNSNodeRolePolicy" && "$STACK" != "dataplane" && "$STACK" != "all" ]]; then
  echo "Error: --enable-external-dns-node-role-policy only applies to stack 'dataplane' or 'all'"
  exit 1
fi

# Fetch existing parameters from a CloudFormation stack and format them as --parameter-overrides arguments.
get_parameter_overrides() {
  local stack_name=$1
  shift
  local excluded_keys=("$@")
  aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --query 'Stacks[0].Parameters[*].[ParameterKey,ParameterValue]' \
    --output text | while read -r key value; do
      for excluded_key in "${excluded_keys[@]}"; do
        if [[ "$key" == "$excluded_key" ]]; then
          continue 2
        fi
      done
      echo "${key}=${value}"
    done
}

update_stack() {
  local stack_name=$1
  local template_file=$2
  local extra_overrides="${3:-}"
  local excluded_parameter_keys="${4:-}"

  echo "Updating stack: ${stack_name} ..."

  # Check if stack exists
  if ! aws cloudformation describe-stacks --stack-name "$stack_name" &>/dev/null; then
    echo "Error: Stack ${stack_name} does not exist. Please run tidbcloud-byoc-setup.sh first."
    exit 1
  fi

  # Fetch existing parameters
  local overrides
  local excluded_keys=()
  if [[ -n "$excluded_parameter_keys" ]]; then
    IFS=',' read -ra excluded_keys <<< "$excluded_parameter_keys"
  fi
  overrides=$(get_parameter_overrides "$stack_name" "${excluded_keys[@]+"${excluded_keys[@]}"}")

  # shellcheck disable=SC2086
  aws cloudformation deploy \
    --stack-name "$stack_name" \
    --template-file "$template_file" \
    --parameter-overrides $overrides $extra_overrides \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

  echo "Stack ${stack_name} updated successfully (or no changes were necessary)."
}

deploy_overrides=""
if [[ -n "$AdditionalO11yHostedZoneIds" ]]; then
  deploy_overrides="AdditionalO11yHostedZoneIds=$(hz_ids_to_arns "$AdditionalO11yHostedZoneIds")"
fi

dataplane_overrides=""
dataplane_excluded_parameter_keys=""
[[ -n "$AdditionalPCAArns" ]] && dataplane_overrides="AdditionalPCAArns=$AdditionalPCAArns"
if [[ -n "$AdditionalTidbHostedZoneIds" ]]; then
  dataplane_overrides="$dataplane_overrides AdditionalHostedZoneIds=$(hz_ids_to_arns "$AdditionalTidbHostedZoneIds")"
fi
if [[ -n "$EnableExternalDNSNodeRolePolicy" ]]; then
  dataplane_overrides="$dataplane_overrides EnableExternalDNSNodeRolePolicy=$EnableExternalDNSNodeRolePolicy"
  dataplane_excluded_parameter_keys="EnableExternalDNSNodeRolePolicy"
fi

o11y_overrides=""
if [[ -n "$AdditionalO11yHostedZoneIds" ]]; then
  o11y_overrides="AdditionalO11yHostedZoneIds=$(hz_ids_to_arns "$AdditionalO11yHostedZoneIds")"
fi

case "$STACK" in
  deploy)
    update_stack "tidbcloud-byoc-setup-deploy" "./tidbcloud-byoc-setup-deploy.yaml" "$deploy_overrides"
    ;;
  dataplane)
    update_stack "tidbcloud-byoc-setup-dataplane" "./tidbcloud-byoc-setup-dataplane.yaml" "$dataplane_overrides" "$dataplane_excluded_parameter_keys"
    ;;
  o11y)
    update_stack "tidbcloud-byoc-setup-o11y" "./tidbcloud-byoc-setup-o11y.yaml" "$o11y_overrides"
    ;;
  all)
    update_stack "tidbcloud-byoc-setup-deploy" "./tidbcloud-byoc-setup-deploy.yaml" "$deploy_overrides"
    update_stack "tidbcloud-byoc-setup-dataplane" "./tidbcloud-byoc-setup-dataplane.yaml" "$dataplane_overrides" "$dataplane_excluded_parameter_keys"
    update_stack "tidbcloud-byoc-setup-o11y" "./tidbcloud-byoc-setup-o11y.yaml" "$o11y_overrides"
    ;;
  *)
    echo "Error: unknown stack '$STACK'. Must be one of: deploy, dataplane, o11y, all"
    exit 1
    ;;
esac
