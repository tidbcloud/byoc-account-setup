
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 6 ]]; then
  echo "Usage: $0 <ControlPlaneAccountId> <ClinicAccountId> <TidbHostedZoneId> <O11yHostedZoneId> <TidbPCAArn> <O11yGlobalRoleArn> [GithubRunnerGoogleAccountId]"
  exit 1
fi

ControlPlaneAccountId=$1
ClinicAccountId=$2
TidbHostedZoneId=$3
O11yHostedZoneId=$4
TidbPCAArn=$5
O11yGlobalRoleArn=$6
GithubRunnerGoogleAccountId=${7:-114667344163696279999}

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
               O11yGlobalRoleArn=$O11yGlobalRoleArn \
  --capabilities CAPABILITY_NAMED_IAM
