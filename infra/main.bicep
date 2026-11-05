targetScope = 'subscription'

type StressTarget = {
  @description('Full resource ID of an existing SQL logical server; not modified by this deployment.')
  serverResourceId: string
  @description('Existing stress database on that server.')
  databaseName: string
}

@description('Resource group to create or update in the selected subscription. For an existing group, retain its original location.')
param controlResourceGroupName string

@description('Region for the resource group and new control resources.')
param location string

@description('Tags applied to the control resource group and new resources.')
param tags object

@description('Globally unique name of the dedicated control SQL server; never use a stress server name.')
@minLength(1)
@maxLength(63)
param controlServerName string

@description('Name of the job database.')
param jobDatabaseName string

@description('Name of the Elastic Job Agent.')
param jobAgentName string

@description('Elastic Job Agent service level.')
@allowed(['JA100', 'JA200', 'JA400', 'JA800'])
param jobAgentSkuName string

@description('Standard DTU SKU for the always-on job database.')
@allowed(['S1', 'S2', 'S3'])
param jobDatabaseSkuName string

@description('Name of the user-assigned managed identity for the agent.')
param managedIdentityName string

@description('Display name of the existing Entra administrator user or group.')
@minLength(1)
param entraAdministratorName string

@description('Object ID of the existing Entra administrator user or group in the selected subscription tenant.')
@minLength(36)
@maxLength(36)
param entraAdministratorObjectId string

@description('Type of the existing Entra administrator.')
@allowed(['Group', 'User'])
param entraAdministratorPrincipalType string

@description('Allow Azure services through the control SQL firewall (0.0.0.0 rule). Broad Azure-wide access, needed for public Elastic Jobs connectivity in this demo.')
param allowAzureServices bool

@description('Public IPv4 firewall rules for administrators; use narrow ranges, ideally startIpAddress = endIpAddress.')
param administratorFirewallRules {
  name: string
  startIpAddress: string
  endIpAddress: string
}[]

@description('Existing laboratory targets, included in deployment outputs only; their public connectivity must be configured separately.')
@minLength(1)
param stressTargets StressTarget[]

resource controlGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: controlResourceGroupName
  location: location
  tags: tags
}

module control './modules/control.bicep' = {
  name: 'elastic-jobs-control'
  scope: controlGroup
  params: {
    location: location
    tags: tags
    controlServerName: controlServerName
    jobDatabaseName: jobDatabaseName
    jobAgentName: jobAgentName
    jobAgentSkuName: jobAgentSkuName
    jobDatabaseSkuName: jobDatabaseSkuName
    managedIdentityName: managedIdentityName
    entraAdministratorName: entraAdministratorName
    entraAdministratorObjectId: entraAdministratorObjectId
    entraAdministratorPrincipalType: entraAdministratorPrincipalType
    allowAzureServices: allowAzureServices
    administratorFirewallRules: administratorFirewallRules
  }
}

output controlResourceGroupId string = controlGroup.id
output controlServerResourceId string = control.outputs.controlServerResourceId
output jobServerFqdn string = control.outputs.jobServerFqdn
output jobDatabaseResourceId string = control.outputs.jobDatabaseResourceId
output deployedJobDatabaseName string = control.outputs.jobDatabaseName
output jobAgentResourceId string = control.outputs.jobAgentResourceId
output jobIdentityResourceId string = control.outputs.jobIdentityResourceId
output jobIdentityPrincipalId string = control.outputs.jobIdentityPrincipalId
output jobIdentityName string = control.outputs.jobIdentityName
output existingStressTargets array = stressTargets
output nextSteps string = 'Verify public firewall access on all three SQL servers, then install SQL permissions and disabled jobs. No workload has been started.'
