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
param o11yDnsZoneResourceGroupName string
param o11yDnsZoneName string
param deploymentAppId string
param dataplaneAppId string
param deploymentResourceGroupName string
param acrResourceGroupName string
param acrCreatedBySetup bool = true
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
param o11yAksControlPlaneIdentityName string
param o11yAksKubeletIdentityName string

var setupStateSchemaVersion = '1'
var o11yRegionalServerIdentityName = 'o11y-regional-server'
var o11yVmbackupIdentityName = 'o11y-vmbackup'
var o11yLokiIdentityName = 'o11y-loki'
var o11yVeleroIdentityName = 'o11y-velero'
var o11yAgicIdentityName = 'o11y-agic'

output setupState object = {
  schemaVersion: setupStateSchemaVersion
  deployName: deployName
  location: location
  tenantId: tenantId
  subscriptionId: subscriptionId
  dnsZoneSubscriptionId: dnsZoneSubscriptionId
  dnsZoneResourceGroupName: dnsZoneResourceGroupName
  dnsZoneName: dnsZoneName
  o11yDnsZoneResourceGroupName: o11yDnsZoneResourceGroupName
  o11yDnsZoneName: o11yDnsZoneName
  deploymentAppId: deploymentAppId
  dataplaneAppId: dataplaneAppId
  deploymentResourceGroupName: deploymentResourceGroupName
  acrResourceGroupName: acrResourceGroupName
  acrCreatedBySetup: acrCreatedBySetup
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
  o11yAksControlPlaneIdentityName: o11yAksControlPlaneIdentityName
  o11yAksKubeletIdentityName: o11yAksKubeletIdentityName
  o11yAgicIdentityName: o11yAgicIdentityName
}

output customerOnboarding object = {
  dataplane_app_id: dataplaneAppId
  deployment_app_id: deploymentAppId
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
  o11y_dns_domain: o11yDnsZoneName
  o11y_dns_resource_group: o11yDnsZoneResourceGroupName
  audit_log_storage_account_name: auditLogStorageAccountName
  audit_log_bucket: auditLogContainerName
  storage_accounts_resource_group: storageResourceGroupName
  o11y_identity_resource_group: o11yResourceGroupName
  o11y_aks_resource_group: '${o11yResourceGroupName}-infra'
  o11y_storage_resource_group: '${o11yResourceGroupName}-storage'
  o11y_aks_control_plane_identity_name: o11yAksControlPlaneIdentityName
  o11y_aks_kubelet_identity_name: o11yAksKubeletIdentityName
  o11y_agic_identity_name: o11yAgicIdentityName
  o11y_regional_server_identity_name: o11yRegionalServerIdentityName
  o11y_vmbackup_identity_name: o11yVmbackupIdentityName
  o11y_loki_identity_name: o11yLokiIdentityName
  o11y_velero_identity_name: o11yVeleroIdentityName
}
