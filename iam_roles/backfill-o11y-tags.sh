#!/usr/bin/env bash
# backfill-o11y-tags.sh — Backfill ManagedBy=PingCAP onto existing O11Y resources
#
# Purpose:
#   The O11Y IAM role (#57) only manages resources tagged ManagedBy=PingCAP.
#   Resources created before the tag rollout (e.g. the pm legacy cluster) lack
#   this tag. This script finds the O11Y resources of a TARGET cluster via
#   their `elbv2.k8s.aws/cluster: <cluster-name>` tag and stamps
#   ManagedBy=PingCAP on them, so the tightened IAM can manage them afterwards.
#
# Requires:
#   - AWS credentials that can assume `tidbcloud-dataplane-manager-assumed-role`
#     in the dataplane account (e.g. an SSO/role profile, or run in a workflow
#     with OIDC federation). The dataplane-manager role's trust allows the
#     control-plane account to assume it.
#
# Usage:
#   bash backfill-o11y-tags.sh \
#     --profile <aws-profile> \
#     --cluster <eks-cluster-name> \
#     --dataplane-account 227896186585 \
#     --region us-west-2 \
#     [--dry-run]
#
# Options:
#   --profile <name>          AWS profile used to assume the dataplane role (required)
#   --cluster <name>          EKS cluster name whose resources to backfill (required)
#                             Only resources tagged elbv2.k8s.aws/cluster=<name> are touched.
#   --dataplane-account <id>  AWS account that owns the O11Y resources (default 227896186585)
#   --region <region>         AWS region (default us-west-2)
#   --role-name <name>        dataplane-manager role to assume (default tidbcloud-dataplane-manager-assumed-role)
#   --dry-run                 Only list resources that would be tagged; make no changes
#   -h, --help                Show this help

set -euo pipefail

PROFILE=""
TARGET_CLUSTER=""
DATAPLANE_ACCOUNT="227896186585"
REGION="us-west-2"
ROLE_NAME="tidbcloud-dataplane-manager-assumed-role"
DRY_RUN=false
TAG_KEY="ManagedBy"
TAG_VALUE="PingCAP"

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --cluster) TARGET_CLUSTER="$2"; shift 2 ;;
    --dataplane-account) DATAPLANE_ACCOUNT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --role-name) ROLE_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option '$1'"; usage ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "Error: missing required parameter: --profile"
  usage
fi
if [[ -z "$TARGET_CLUSTER" ]]; then
  echo "Error: missing required parameter: --cluster"
  usage
fi

ROLE_ARN="arn:aws:iam::${DATAPLANE_ACCOUNT}:role/${ROLE_NAME}"

echo "=== Backfilling ${TAG_KEY}=${TAG_VALUE} on resources of cluster ${TARGET_CLUSTER} ==="
echo "  profile:            ${PROFILE}"
echo "  dataplane account:  ${DATAPLANE_ACCOUNT}"
echo "  region:             ${REGION}"
echo "  role:               ${ROLE_ARN}"
echo "  dry-run:            ${DRY_RUN}"
echo

# 1. Assume the dataplane-manager role so the tagging calls run as it.
ASSUME=$(aws sts assume-role \
  --profile "$PROFILE" \
  --role-arn "$ROLE_ARN" \
  --role-session-name "o11y-tag-backfill-$(date +%s)" \
  --output json 2>/dev/null) || {
    echo "Error: failed to assume ${ROLE_ARN} with profile ${PROFILE}" >&2
    echo "The profile must be allowed to sts:AssumeRole into the dataplane account." >&2
    exit 1
  }

export AWS_ACCESS_KEY_ID=$(echo "$ASSUME" | python3 -c "import json,sys;print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME" | python3 -c "import json,sys;print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "$ASSUME" | python3 -c "import json,sys;print(json.load(sys.stdin)['Credentials']['SessionToken'])")
export AWS_DEFAULT_REGION="$REGION"

echo "Assumed role: $(aws sts get-caller-identity --query Arn --output text)"
echo

COUNT_ADDED=0
COUNT_SKIPPED=0

# ec2 create-tags with pre-check (idempotent)
backfill_ec2_tags() {
  local resource_type="$1"
  local resource_ids="$2"
  [[ -z "$resource_ids" ]] && return 0
  while read -r rid; do
    [[ -z "$rid" ]] && continue
    local has_tag
    has_tag=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$rid" "Name=key,Values=${TAG_KEY}" \
      --query 'Tags[0].Value' --output text 2>/dev/null || true)
    if [[ "$has_tag" == "${TAG_VALUE}" ]]; then
      echo "  [skip] ${resource_type} ${rid}: already ${TAG_KEY}=${TAG_VALUE}"
      COUNT_SKIPPED=$((COUNT_SKIPPED+1))
    else
      if $DRY_RUN; then
        echo "  [dry-run] would tag ${resource_type} ${rid} with ${TAG_KEY}=${TAG_VALUE} (current: ${has_tag:-none})"
        COUNT_ADDED=$((COUNT_ADDED+1))
      else
        if aws ec2 create-tags --resources "$rid" --tags "Key=${TAG_KEY},Value=${TAG_VALUE}" >/dev/null 2>&1; then
          echo "  [tagged] ${resource_type} ${rid}"
          COUNT_ADDED=$((COUNT_ADDED+1))
        else
          echo "  [FAILED] ${resource_type} ${rid}"
        fi
      fi
    fi
  done <<< "$resource_ids"
}

# elb add-tags with pre-check (idempotent)
backfill_elb_tags() {
  local resource_type="$1"
  local arns="$2"
  [[ -z "$arns" ]] && return 0
  while read -r arn; do
    [[ -z "$arn" ]] && continue
    local has_tag
    has_tag=$(aws elbv2 describe-tags --resource-arns "$arn" \
      --query 'TagDescriptions[0].Tags[?Key==`'${TAG_KEY}'`].Value | [0]' --output text 2>/dev/null || true)
    if [[ "$has_tag" == "${TAG_VALUE}" ]]; then
      echo "  [skip] ${resource_type} ${arn}: already ${TAG_KEY}=${TAG_VALUE}"
      COUNT_SKIPPED=$((COUNT_SKIPPED+1))
    else
      if $DRY_RUN; then
        echo "  [dry-run] would tag ${resource_type} ${arn} with ${TAG_KEY}=${TAG_VALUE}"
        COUNT_ADDED=$((COUNT_ADDED+1))
      else
        if aws elbv2 add-tags --resource-arns "$arn" --tags "Key=${TAG_KEY},Value=${TAG_VALUE}" >/dev/null 2>&1; then
          echo "  [tagged] ${resource_type} ${arn}"
          COUNT_ADDED=$((COUNT_ADDED+1))
        else
          echo "  [FAILED] ${resource_type} ${arn}"
        fi
      fi
    fi
  done <<< "$arns"
}

echo "--- cluster: ${TARGET_CLUSTER} ---"

# Security groups: one-shot filter by the target cluster's elbv2 tag
SG_IDS=$(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${TARGET_CLUSTER}" \
  --query 'SecurityGroups[].GroupId' --output text 2>/dev/null | tr '\t' '\n')
backfill_ec2_tags "security-group" "$SG_IDS"

# Load balancers: list all, keep those whose elbv2 cluster tag equals the target
ALL_LB=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null | tr '\t' '\n')
LB_ARNS=""
while read -r arn; do
  [[ -z "$arn" ]] && continue
  local_ct=$(aws elbv2 describe-tags --resource-arns "$arn" \
    --query 'TagDescriptions[0].Tags[?Key==`elbv2.k8s.aws/cluster`].Value | [0]' --output text 2>/dev/null || true)
  if [[ "$local_ct" == "$TARGET_CLUSTER" ]]; then
    LB_ARNS="$LB_ARNS$arn"$'\n'
  fi
done <<< "$ALL_LB"
backfill_elb_tags "load-balancer" "$LB_ARNS"

# Target groups: list all, keep those whose elbv2 cluster tag equals the target
ALL_TG=$(aws elbv2 describe-target-groups \
  --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null | tr '\t' '\n')
TG_ARNS=""
while read -r arn; do
  [[ -z "$arn" ]] && continue
  local_ct=$(aws elbv2 describe-tags --resource-arns "$arn" \
    --query 'TagDescriptions[0].Tags[?Key==`elbv2.k8s.aws/cluster`].Value | [0]' --output text 2>/dev/null || true)
  if [[ "$local_ct" == "$TARGET_CLUSTER" ]]; then
    TG_ARNS="$TG_ARNS$arn"$'\n'
  fi
done <<< "$ALL_TG"
backfill_elb_tags "target-group" "$TG_ARNS"

echo
echo "=== Done ==="
echo "  tagged/scheduled: ${COUNT_ADDED}"
echo "  skipped (already tagged): ${COUNT_SKIPPED}"
