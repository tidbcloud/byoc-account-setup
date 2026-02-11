#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --stack <stack>

Required:
  --stack <stack>   The stack to update, one of 'deploy', 'dataplane', 'o11y', or 'all'

Options:
  -h, --help        Show this help message

This script automatically fetches existing parameters from deployed stacks.
No need to pass parameters again.
EOF
  exit 1
}

STACK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      STACK="$2"; shift 2 ;;
    -h|--help)
      usage ;;
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

# Fetch existing parameters from a CloudFormation stack and format them as --parameter-overrides arguments.
get_parameter_overrides() {
  local stack_name=$1
  aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --query 'Stacks[0].Parameters[*].[ParameterKey,ParameterValue]' \
    --output text | while read -r key value; do
      echo "${key}=${value}"
    done
}

update_stack() {
  local stack_name=$1
  local template_file=$2

  echo "Updating stack: ${stack_name} ..."

  # Check if stack exists
  if ! aws cloudformation describe-stacks --stack-name "$stack_name" &>/dev/null; then
    echo "Error: Stack ${stack_name} does not exist. Please run tidbcloud-byoc-setup.sh first."
    exit 1
  fi

  # Fetch existing parameters
  local overrides
  overrides=$(get_parameter_overrides "$stack_name")

  # shellcheck disable=SC2086
  aws cloudformation deploy \
    --stack-name "$stack_name" \
    --template-file "$template_file" \
    --parameter-overrides $overrides \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

  echo "Stack ${stack_name} updated successfully (or no changes were necessary)."
}

case "$STACK" in
  deploy)
    update_stack "tidbcloud-byoc-setup-deploy" "./tidbcloud-byoc-setup-deploy.yaml"
    ;;
  dataplane)
    update_stack "tidbcloud-byoc-setup-dataplane" "./tidbcloud-byoc-setup-dataplane.yaml"
    ;;
  o11y)
    update_stack "tidbcloud-byoc-setup-o11y" "./tidbcloud-byoc-setup-o11y.yaml"
    ;;
  all)
    update_stack "tidbcloud-byoc-setup-deploy" "./tidbcloud-byoc-setup-deploy.yaml"
    update_stack "tidbcloud-byoc-setup-dataplane" "./tidbcloud-byoc-setup-dataplane.yaml"
    update_stack "tidbcloud-byoc-setup-o11y" "./tidbcloud-byoc-setup-o11y.yaml"
    ;;
  *)
    echo "Error: unknown stack '$STACK'. Must be one of: deploy, dataplane, o11y, all"
    exit 1
    ;;
esac
