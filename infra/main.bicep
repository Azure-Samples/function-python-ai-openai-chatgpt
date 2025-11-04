targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources & Flex Consumption Function App')
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'norwayeast'
  'southafricanorth'
  'southcentralus'
  'southindia'
  'swedencentral'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus'
  'westus3'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

param vnetEnabled bool = false
param apiServiceName string = ''
param apiUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
@description('Id of the user identity to be used for testing and debugging. This is not required in production. Leave empty if not needed.')
param principalId string = ''

@description('Name for the AI project resources.')
param aiProjectName string = 'simple-agent'

@description('Friendly name for your Azure AI resource')
param aiProjectFriendlyName string = 'Simple AI Agent Project'

@description('Description of your Azure AI resource displayed in AI studio')
param aiProjectDescription string = 'This is a simple AI agent project for Azure Functions.'

@description('Name of the Azure AI Search account')
param aiSearchName string = 'agent-ai-search'

@description('Name for capabilityHost.')
param accountCapabilityHostName string = 'caphostacc'

@description('Name for capabilityHost.')
param projectCapabilityHostName string = 'caphostproj'

@description('Name of the Azure AI Services account')
param aiServicesName string = 'agent-ai-services'

@description('Model name for deployment')
param modelName string = 'gpt-4o-mini'

@description('Model format for deployment')
param modelFormat string = 'OpenAI'

@description('Model version for deployment')
param modelVersion string = '2024-07-18'

@description('Model deployment SKU name')
param modelSkuName string = 'GlobalStandard'

@description('Model deployment capacity')
param modelCapacity int = 50

@description('Name of the Cosmos DB account for agent thread storage')
param cosmosDbName string = 'agent-ai-cosmos'

@description('The AI Service Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiServiceAccountResourceId string = ''

@description('The Ai Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchServiceResourceId string = ''

@description('The Ai Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiStorageAccountResourceId string = ''

@description('The Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiCosmosDbAccountResourceId string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'
var projectName = toLower('${aiProjectName}')

// Create a short, unique suffix, that will be unique to each resource group
var uniqueSuffix = toLower(uniqueString(subscription().id, environmentName, location))

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User assigned managed identity to be used by the function app to reach storage and other dependencies
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

// Monitor application with Azure Monitor - Log Analytics and Application Insights
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}
 
module monitoring 'br/public:avm/res/insights/component:0.6.0' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

// Backing storage for Azure functions backend API
module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Disable local authentication methods as per policy
    dnsEndpointType: 'Standard'
    publicNetworkAccess: vnetEnabled ? 'Disabled' : 'Enabled'
    // When vNet is enabled, restrict access but allow Azure services
    networkAcls: vnetEnabled ? {
      defaultAction: 'Deny'
      bypass: 'AzureServices' // Allow Azure services including AI Agent service
    } : {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [{name: deploymentStorageContainerName}]
    }
    queueServices: {
      queues: [
        { name: 'input' }
        { name: 'output' }
      ]
    }
    minimumTlsVersion: 'TLS1_2'  // Enforcing TLS 1.2 for better security
    location: location
    tags: tags
  }
}

// Dependent resources for the Azure AI workspace
module aiDependencies './agent/standard-dependent-resources.bicep' = {
  name: 'dependencies${projectName}${uniqueSuffix}deployment'
  scope: rg
  params: {
    location: location
    storageName: 'stai${uniqueSuffix}'
    aiServicesName: '${aiServicesName}${uniqueSuffix}'
    aiSearchName: '${aiSearchName}${uniqueSuffix}'
    cosmosDbName: '${cosmosDbName}${uniqueSuffix}'
    tags: tags

     // Model deployment parameters
     modelName: modelName
     modelFormat: modelFormat
     modelVersion: modelVersion
     modelSkuName: modelSkuName
     modelCapacity: modelCapacity  
     modelLocation: location

     aiServiceAccountResourceId: aiServiceAccountResourceId
     aiSearchServiceResourceId: aiSearchServiceResourceId
     aiStorageAccountResourceId: aiStorageAccountResourceId
     aiCosmosDbAccountResourceId: aiCosmosDbAccountResourceId
    }
}

module aiProject './agent/standard-ai-project.bicep' = {
  name: '${projectName}${uniqueSuffix}deployment'
  scope: rg
  params: {
    // workspace organization
    aiServicesAccountName: aiDependencies.outputs.aiServicesName
    aiProjectName: '${projectName}${uniqueSuffix}'
    aiProjectFriendlyName: aiProjectFriendlyName
    aiProjectDescription: aiProjectDescription
    location: location
    tags: tags
    
    // dependent resources
    aiSearchName: aiDependencies.outputs.aiSearchName
    aiSearchSubscriptionId: aiDependencies.outputs.aiSearchServiceSubscriptionId
    aiSearchResourceGroupName: aiDependencies.outputs.aiSearchServiceResourceGroupName
    storageAccountName: aiDependencies.outputs.storageAccountName
    storageAccountSubscriptionId: aiDependencies.outputs.storageAccountSubscriptionId
    storageAccountResourceGroupName: aiDependencies.outputs.storageAccountResourceGroupName
    cosmosDbAccountName: aiDependencies.outputs.cosmosDbAccountName
    cosmosDbAccountSubscriptionId: aiDependencies.outputs.cosmosDbAccountSubscriptionId
    cosmosDbAccountResourceGroupName: aiDependencies.outputs.cosmosDbAccountResourceGroupName
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.12'
    storageAccountName: storage.outputs.name
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    appSettings: {
      PROJECT_ENDPOINT: aiProject.outputs.projectEndpoint
      MODEL_DEPLOYMENT_NAME: modelName
      AZURE_OPENAI_ENDPOINT: 'https://${aiDependencies.outputs.aiServicesName}.openai.azure.com/'
      AZURE_OPENAI_DEPLOYMENT_NAME: modelName
      AZURE_CLIENT_ID: apiUserAssignedIdentity.outputs.clientId
      STORAGE_CONNECTION__queueServiceUri: 'https://${storage.outputs.name}.queue.${environment().suffixes.storage}'
      STORAGE_CONNECTION__clientId: apiUserAssignedIdentity.outputs.clientId
      STORAGE_CONNECTION__credential: 'managedidentity'
      PROJECT_ENDPOINT__clientId: apiUserAssignedIdentity.outputs.clientId
    }
    virtualNetworkSubnetId: ''
  }
}

module projectRoleAssignments './agent/standard-ai-project-role-assignments.bicep' = {
  name: 'aiprojectroleassignments${projectName}${uniqueSuffix}deployment'
  scope: rg
  params: {
    aiProjectPrincipalId: aiProject.outputs.aiProjectPrincipalId
    userPrincipalId: principalId
    allowUserIdentityPrincipal: !empty(principalId) // Enable user identity role assignments
    aiServicesName: aiDependencies.outputs.aiServicesName
    aiSearchName: aiDependencies.outputs.aiSearchName
    aiCosmosDbName: aiDependencies.outputs.cosmosDbAccountName
    aiStorageAccountName: aiDependencies.outputs.storageAccountName
    integrationStorageAccountName: storage.outputs.name
    functionAppManagedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    allowFunctionAppIdentityPrincipal: true // Enable function app identity role assignments
  }
}

module aiProjectCapabilityHost './agent/standard-ai-project-capability-host.bicep' = {
  name: 'capabilityhost${projectName}${uniqueSuffix}deployment'
  scope: rg
  params: {
    aiServicesAccountName: aiDependencies.outputs.aiServicesName
    projectName: aiProject.outputs.aiProjectName
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    cosmosDbConnection: aiProject.outputs.cosmosDbConnection

    accountCapHost: '${accountCapabilityHostName}${uniqueSuffix}'
    projectCapHost: '${projectCapabilityHostName}${uniqueSuffix}'
  }
  dependsOn: [ projectRoleAssignments ]
}

module postCapabilityHostCreationRoleAssignments './agent/post-capability-host-role-assignments.bicep' = {
  name: 'postcaphostra${projectName}${uniqueSuffix}deployment'
  scope: rg
  params: {
    aiProjectPrincipalId: aiProject.outputs.aiProjectPrincipalId
    aiProjectWorkspaceId: aiProject.outputs.projectWorkspaceId
    aiStorageAccountName: aiDependencies.outputs.storageAccountName
    cosmosDbAccountName: aiDependencies.outputs.cosmosDbAccountName
  }
  dependsOn: [ aiProjectCapabilityHost ]
}

// Define the configuration object locally to pass to the modules
var storageEndpointConfig = {
  enableBlob: true  // Required for AzureWebJobsStorage, .zip deployment, Event Hubs trigger and Timer trigger checkpointing
  enableQueue: true  // Required for Durable Functions and MCP trigger
  enableTable: false  // Required for Durable Functions and OpenAI triggers and bindings
  enableFiles: false   // Not required, used in legacy scenarios
  allowUserIdentityPrincipal: !empty(principalId)   // Allow interactive user identity to access for testing and debugging
}

// Consolidated Role Assignments
module rbac 'app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    userIdentityPrincipalId: principalId
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    allowUserIdentityPrincipal: storageEndpointConfig.allowUserIdentityPrincipal
  }
}

// Virtual Network & private endpoint to blob storage (disabled for now)
// module serviceVirtualNetwork 'app/vnet.bicep' =  if (vnetEnabled) {
//   name: 'serviceVirtualNetwork'
//   scope: rg
//   params: {
//     location: location
//     tags: tags
//     vNetName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
//   }
// }

// module storagePrivateEndpoint 'app/storage-PrivateEndpoint.bicep' = if (vnetEnabled) {
//   name: 'servicePrivateEndpoint'
//   scope: rg
//   params: {
//     location: location
//     tags: tags
//     virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
//     subnetName: serviceVirtualNetwork.outputs.peSubnetName
//     resourceName: storage.outputs.name
//     enableBlob: storageEndpointConfig.enableBlob
//     enableQueue: storageEndpointConfig.enableQueue
//     enableTable: storageEndpointConfig.enableTable
//   }
// }

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.connectionString
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_API_NAME string = api.outputs.SERVICE_API_NAME
output SERVICE_API_URI string = 'https://${api.outputs.SERVICE_API_NAME}.azurewebsites.net'
output AZURE_FUNCTION_APP_NAME string = api.outputs.SERVICE_API_NAME
output RESOURCE_GROUP string = rg.name
output STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AI_SERVICES_NAME string = aiDependencies.outputs.aiServicesName

// AI Foundry outputs
output PROJECT_ENDPOINT string = aiProject.outputs.projectEndpoint
output MODEL_DEPLOYMENT_NAME string = modelName
output AZURE_OPENAI_ENDPOINT string = 'https://${aiDependencies.outputs.aiServicesName}.openai.azure.com/'
output AZURE_OPENAI_DEPLOYMENT_NAME string = modelName
output AZURE_CLIENT_ID string = apiUserAssignedIdentity.outputs.clientId
output STORAGE_CONNECTION__queueServiceUri string = 'https://${storage.outputs.name}.queue.${environment().suffixes.storage}'
