// Creates Azure dependent resources for Azure AI studio

@description('Azure region of the deployment')
param location string = resourceGroup().location

@description('Tags to add to the resources')
param tags object = {}

@description('AI services name')
param aiServicesName string

@description('The name of the AI Search resource')
param aiSearchName string

@description('The name of the Cosmos DB account')
param cosmosDbName string

@description('Name of the storage account')
param storageName string

@description('Model name for deployment')
param modelName string 

@description('Model format for deployment')
param modelFormat string 

@description('Model version for deployment')
param modelVersion string 

@description('Model deployment SKU name')
param modelSkuName string 

@description('Model deployment capacity')
param modelCapacity int 

@description('Model/AI Resource deployment location')
param modelLocation string 

@description('The AI Service Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiServiceAccountResourceId string

@description('The AI Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchServiceResourceId string 

@description('The AI Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiStorageAccountResourceId string 

@description('The AI Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiCosmosDbAccountResourceId string

var aiServiceExists = aiServiceAccountResourceId != ''
var acsExists = aiSearchServiceResourceId != ''
var aiStorageExists = aiStorageAccountResourceId != ''
var cosmosExists = aiCosmosDbAccountResourceId != ''

// Create an AI Service account and model deployment if it doesn't already exist



resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = if(!aiServiceExists) {
  name: aiServicesName
  location: modelLocation
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: toLower('${(aiServicesName)}')
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }    
    publicNetworkAccess: 'Enabled'
    // API-key based auth is not supported for the Agent service and policy requires it to be disabled
    disableLocalAuth: true
  }
}
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview'= if(!aiServiceExists){
  parent: aiServices
  name: modelName
  sku : {
    capacity: modelCapacity
    name: modelSkuName
  }
  properties: {
    model:{
      name: modelName
      format: modelFormat
      version: modelVersion
    }
  }
}

// Create an AI Search Service if it doesn't already exist
resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' = if(!acsExists) {
  name: aiSearchName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: true
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    hostingMode: 'default'
    partitionCount: 1
    publicNetworkAccess: 'enabled'
    replicaCount: 1
    semanticSearch: 'disabled'
  }
  sku: {
    name: 'standard'
  }
}

// Create a Storage account if it doesn't already exist

param sku string = 'Standard_LRS'

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' = if(!aiStorageExists) {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: sku
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      virtualNetworkRules: []
    }
    allowSharedKeyAccess: false
  }
}

// Create a Cosmos DB Account if it doesn't already exist

var canaryRegions = ['eastus2euap', 'centraluseuap']
var cosmosDbRegion = contains(canaryRegions, location) ? 'eastus2' : location
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = if(!cosmosExists) {
  name: cosmosDbName
  location: cosmosDbRegion
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    enableFreeTier: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
  }
}

// Outputs

output aiServicesName string = aiServicesName
output aiservicesID string = aiServices.id
output aiServiceAccountResourceGroupName string = resourceGroup().name
output aiServiceAccountSubscriptionId string = subscription().subscriptionId 

output aiSearchName string = aiSearchName  
output aisearchID string = aiSearch.id
output aiSearchServiceResourceGroupName string = resourceGroup().name
output aiSearchServiceSubscriptionId string = subscription().subscriptionId

output storageAccountName string = storageName
output storageId string = storage.id
output storageAccountResourceGroupName string = resourceGroup().name
output storageAccountSubscriptionId string = subscription().subscriptionId

output cosmosDbAccountName string = cosmosDbName
output cosmosDbAccountId string = cosmosDbAccount.id
output cosmosDbAccountResourceGroupName string = resourceGroup().name
output cosmosDbAccountSubscriptionId string = subscription().subscriptionId
