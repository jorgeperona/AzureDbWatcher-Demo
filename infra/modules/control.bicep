targetScope = 'resourceGroup'

@description('Region of new control resources.')
param location string
@description('Resource tags.')
param tags object
@description('Dedicated control SQL server name.')
param controlServerName string
@description('Job database name.')
param jobDatabaseName string
@description('Job agent name.')
param jobAgentName string
@description('Job agent service level.')
param jobAgentSkuName string
@description('Standard database SKU.')
param jobDatabaseSkuName string
@description('User-assigned managed identity name.')
param managedIdentityName string
@description('Existing Entra administrator display name.')
param entraAdministratorName string
@description('Existing Entra administrator object ID.')
param entraAdministratorObjectId string
@description('Existing Entra administrator principal type.')
param entraAdministratorPrincipalType string
@description('Enable the Azure-wide SQL firewall exception for public agent connectivity.')
param allowAzureServices bool
@description('Explicit administrator IPv4 firewall rules.')
param administratorFirewallRules {
  name: string
  startIpAddress: string
  endIpAddress: string
}[]

resource jobIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

resource controlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: controlServerName
  location: location
  tags: tags
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdministratorName
      sid: entraAdministratorObjectId
      principalType: entraAdministratorPrincipalType
      tenantId: subscription().tenantId
    }
  }
}

resource azureServicesRule 'Microsoft.Sql/servers/firewallRules@2023-08-01' = if (allowAzureServices) {
  parent: controlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource administratorRules 'Microsoft.Sql/servers/firewallRules@2023-08-01' = [
  for rule in administratorFirewallRules: {
    parent: controlServer
    name: rule.name
    properties: {
      startIpAddress: rule.startIpAddress
      endIpAddress: rule.endIpAddress
    }
  }
]

resource jobDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: controlServer
  name: jobDatabaseName
  location: location
  tags: tags
  sku: {
    name: jobDatabaseSkuName
    tier: 'Standard'
  }
  properties: {
    createMode: 'Default'
    requestedBackupStorageRedundancy: 'Local'
  }
}

resource jobAgent 'Microsoft.Sql/servers/jobAgents@2023-08-01' = {
  parent: controlServer
  name: jobAgentName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${jobIdentity.id}': {}
    }
  }
  sku: {
    name: jobAgentSkuName
  }
  properties: {
    databaseId: jobDatabase.id
  }
}

output controlServerResourceId string = controlServer.id
output jobServerFqdn string = controlServer.properties.fullyQualifiedDomainName
output jobDatabaseResourceId string = jobDatabase.id
output jobDatabaseName string = jobDatabase.name
output jobAgentResourceId string = jobAgent.id
output jobIdentityResourceId string = jobIdentity.id
output jobIdentityPrincipalId string = jobIdentity.properties.principalId
output jobIdentityName string = jobIdentity.name
