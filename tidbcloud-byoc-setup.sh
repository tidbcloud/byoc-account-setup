
ControlPlaneAccountId=$1
ClinicAccountId=$2
TidbHostedZoneId=$3
O11yHostedZoneId=$4
TidbPCAArn=$4
GithubRunnerGoogleAccountId=${5:-114667344163696279999}

aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-deploy \
  --template-body file://tidbcloud-byoc-setup-deploy.yaml \
  --parameters ParameterKey=ControlPlaneAccountId,ParameterValue=$ControlPlaneAccountId \
               ParameterKey=GithubRunnerGoogleAccountId,ParameterValue=$GithubRunnerGoogleAccountId \
               ParameterKey=O11yHostedZoneId,ParameterValue=$O11yHostedZoneId \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-dataplane \
  --template-body file://tidbcloud-byoc-setup-dataplane.yaml \
  --parameters ParameterKey=ControlPlaneAccountId,ParameterValue=$ControlPlaneAccountId \
               ParameterKey=HostedZoneId,ParameterValue=$TidbHostedZoneId \
               ParameterKey=PCAArn,ParameterValue=$TidbPCAArn \
               ParameterKey=ClinicAccountId,ParameterValue=$ClinicAccountId \
               ParameterKey=GithubRunnerGoogleAccountId,ParameterValue=$GithubRunnerGoogleAccountId \
               ParameterKey=O11yHostedZoneId,ParameterValue=Z0445973180UDOPUM7N9G \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation deploy \
  --stack-name tidbcloud-byoc-setup-o11y \
  --template-body file://tidbcloud-byoc-setup-o11y.yaml \
  --parameters ParameterKey=O11yHostedZoneId,ParameterValue=$O11yHostedZoneId \
  --capabilities CAPABILITY_NAMED_IAM