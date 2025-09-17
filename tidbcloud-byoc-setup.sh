
ControlPlaneAccountId=$1
ClinicAccountId=$2
TidbHostedZoneId=$3
O11yHostedZoneId=$4
TidbPCAArn=$5
GithubRunnerGoogleAccountId=${6:-114667344163696279999}

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
  --capabilities CAPABILITY_NAMED_IAM