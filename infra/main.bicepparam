using './main.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION')
param controlResourceGroupName = readEnvironmentVariable('CONTROL_RESOURCE_GROUP')
param tags = json(readEnvironmentVariable('RESOURCE_TAGS_JSON'))
param controlServerName = readEnvironmentVariable('CONTROL_SERVER_NAME')
param jobDatabaseName = readEnvironmentVariable('JOB_DATABASE_NAME')
param jobAgentName = readEnvironmentVariable('JOB_AGENT_NAME')
param jobAgentSkuName = readEnvironmentVariable('JOB_AGENT_SKU')
param jobDatabaseSkuName = readEnvironmentVariable('JOB_DATABASE_SKU')
param managedIdentityName = readEnvironmentVariable('MANAGED_IDENTITY_NAME')
param entraAdministratorName = readEnvironmentVariable('ENTRA_ADMIN_NAME')
param entraAdministratorObjectId = readEnvironmentVariable('ENTRA_ADMIN_OBJECT_ID')
param entraAdministratorPrincipalType = readEnvironmentVariable('ENTRA_ADMIN_TYPE')
param allowAzureServices = json(readEnvironmentVariable('ALLOW_AZURE_SERVICES'))
param administratorFirewallRules = json(readEnvironmentVariable('ADMIN_FIREWALL_RULES_JSON'))
var stressSubscriptionId = readEnvironmentVariable('STRESS_SUBSCRIPTION_ID')
var stressResourceGroup = readEnvironmentVariable('STRESS_RESOURCE_GROUP')
var stressServer01 = readEnvironmentVariable('STRESS_SERVER_01')
var stressServer02 = readEnvironmentVariable('STRESS_SERVER_02')

param stressTargets = [
  {
    serverResourceId: '/subscriptions/${stressSubscriptionId}/resourceGroups/${stressResourceGroup}/providers/Microsoft.Sql/servers/${stressServer01}'
    databaseName: readEnvironmentVariable('STRESS_DATABASE_01')
  }
  {
    serverResourceId: '/subscriptions/${stressSubscriptionId}/resourceGroups/${stressResourceGroup}/providers/Microsoft.Sql/servers/${stressServer02}'
    databaseName: readEnvironmentVariable('STRESS_DATABASE_02')
  }
]
