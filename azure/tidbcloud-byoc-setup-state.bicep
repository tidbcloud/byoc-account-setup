targetScope = 'subscription'

// Durable onboarding state stored in the customer subscription.
// This stack intentionally manages no customer workload resources; its outputs
// are the canonical handoff record used by update scripts and auto-deploy.

param deployName string
param location string
param tenantId string
param subscriptionId string
param dnsZoneSubscriptionId string
param dnsZoneResourceGroupName string
param dnsZoneName string
param deploymentAppId string
param dataplaneAppId string
param deploymentResourceGroupName string
param acrResourceGroupName string
param storageResourceGroupName string
param identitiesResourceGroupName string
param o11yResourceGroupName string
param deployStackName string
param initialDeployAccessStackName string
param dataplaneStackName string
param o11yStackName string
param stateStackName string
param acrName string
param acrResourceId string
param acrLoginServer string
param auditLogStorageAccountName string
param auditLogContainerName string
param aksAdminGroupName string
param aksAdminGroupObjectId string
param aksControlPlaneIdentityName string
param aksKubeletIdentityName string

var setupStateSchemaVersion = '1'
var customerOnboardingSchemaVersion = '1'

output setupState object = {
  schemaVersion: setupStateSchemaVersion
  deployName: deployName
  location: location
  tenantId: tenantId
  subscriptionId: subscriptionId
  dnsZoneSubscriptionId: dnsZoneSubscriptionId
  dnsZoneResourceGroupName: dnsZoneResourceGroupName
  dnsZoneName: dnsZoneName
  deploymentAppId: deploymentAppId
  dataplaneAppId: dataplaneAppId
  deploymentResourceGroupName: deploymentResourceGroupName
  acrResourceGroupName: acrResourceGroupName
  storageResourceGroupName: storageResourceGroupName
  identitiesResourceGroupName: identitiesResourceGroupName
  o11yResourceGroupName: o11yResourceGroupName
  o11yInfraResourceGroupName: '${o11yResourceGroupName}-infra'
  o11yStorageResourceGroupName: '${o11yResourceGroupName}-storage'
  deployStackName: deployStackName
  initialDeployAccessStackName: initialDeployAccessStackName
  dataplaneStackName: dataplaneStackName
  o11yStackName: o11yStackName
  stateStackName: stateStackName
  revokeInitialDeployAccessCommand: 'bash tidbcloud-byoc-revoke-initial-deploy-access.sh --deploy-name ${deployName} --subscription-id ${subscriptionId} --yes'
  acrName: acrName
  acrResourceId: acrResourceId
  acrLoginServer: acrLoginServer
  auditLogStorageAccountName: auditLogStorageAccountName
  auditLogContainerName: auditLogContainerName
  aksAdminGroupName: aksAdminGroupName
  aksAdminGroupObjectId: aksAdminGroupObjectId
  aksControlPlaneIdentityName: aksControlPlaneIdentityName
  aksKubeletIdentityName: aksKubeletIdentityName
}

output customerOnboarding object = {
  schema_version: customerOnboardingSchemaVersion
  dataplane_app_id: dataplaneAppId
  customer_tenant_id: tenantId
  customer_subscription_id: subscriptionId
  aks_control_plane_identity_name: aksControlPlaneIdentityName
  aks_kubelet_identity_name: aksKubeletIdentityName
  aks_managed_identity_resource_group: identitiesResourceGroupName
  dataplane_admin_group_object_ids: [
    aksAdminGroupObjectId
  ]
  customer_acr_resource_id: acrResourceId
  customer_acr_login_server: acrLoginServer
  tidb_cluster_dns_domain: dnsZoneName
  tidb_cluster_dns_resource_group: dnsZoneResourceGroupName
  audit_log_storage_account_name: auditLogStorageAccountName
  audit_log_bucket: auditLogContainerName
  storage_accounts_resource_group: storageResourceGroupName
  o11y_resource_group_name: o11yResourceGroupName
  o11y_infra_resource_group_name: '${o11yResourceGroupName}-infra'
  o11y_storage_resource_group_name: '${o11yResourceGroupName}-storage'
  o11y_workload_identity_names: {
    regional_server: 'o11y-regional-server'
    vmbackup: 'o11y-vmbackup'
    loki: 'o11y-loki'
    velero: 'o11y-velero'
  }
}
