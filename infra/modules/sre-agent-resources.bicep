// ============================================================================
// SRE Agent Resources Module (Resource-group scoped)
// ============================================================================
// Creates:
//   1. Log Analytics Workspace
//   2. Application Insights (linked to Log Analytics)
//   3. User-Assigned Managed Identity (or references an existing one)
//   4. SRE Agent with full configuration:
//      - knowledgeGraphConfiguration (identity for knowledge graph operations)
//      - actionConfiguration (identity + access level for tool execution)
//      - logConfiguration (App Insights telemetry)
//   5. RBAC role assignments on the deployment resource group
//   6. RBAC role assignments on target resource groups (if any)
//   7. SRE Agent Administrator role for the deploying user
//
// IMPORTANT: The agent MUST have knowledgeGraphConfiguration, actionConfiguration,
// and logConfiguration — without these, it gets permanently stuck in
// BuildingKnowledgeGraph state.
//
// Pattern note: We use separate resource blocks for "new identity" vs
// "existing identity" paths because Bicep's guid() in RBAC assignment names
// must use values calculable at deployment start (resource IDs, not runtime
// properties like principalId).
// ============================================================================

// ─── Parameters ─────────────────────────────────────────────────────────────

@description('Name of the SRE Agent')
param agentName string

@description('Azure region')
param location string

@description('Subscription ID')
param subscriptionId string

@description('Access level')
@allowed(['High', 'Low'])
param accessLevel string

@description('Agent mode')
@allowed(['Review', 'Autonomous', 'ReadOnly'])
param agentMode string

@description('Existing managed identity resource ID (empty = create new)')
param existingManagedIdentityId string = ''

@description('Target resource groups for cross-RG access')
param targetResourceGroups array = []

@description('Target subscription IDs (parallel to targetResourceGroups)')
param targetSubscriptions array = []

@description('Tags for all resources')
param tags object = {}

// ─── Variables ──────────────────────────────────────────────────────────────

var uniqueSuffix = uniqueString(subscriptionId, resourceGroup().name, agentName)
var shouldCreateIdentity = empty(existingManagedIdentityId)
var identityName = '${agentName}-identity-${uniqueSuffix}'
var workspaceName = '${agentName}-workspace-${uniqueSuffix}'
var appInsightsName = '${agentName}-appinsights-${uniqueSuffix}'

// Role definition IDs per access level
var roleDefinitions = {
  Low: [
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
  ]
  High: [
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    '43d0d8ad-25c7-4714-9337-8ba259a9fe05' // Monitoring Reader
    'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
  ]
}

// ─── Log Analytics Workspace ────────────────────────────────────────────────

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ─── Application Insights ───────────────────────────────────────────────────

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    Request_Source: 'SreAgent'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// ─── User-Assigned Managed Identity ─────────────────────────────────────────

// Create new identity (default path)
#disable-next-line BCP073
resource newIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = if (shouldCreateIdentity) {
  name: identityName
  location: location
  tags: tags
}

// Reference existing identity
resource existingIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = if (!shouldCreateIdentity) {
  name: last(split(existingManagedIdentityId, '/'))
  scope: resourceGroup(split(existingManagedIdentityId, '/')[2], split(existingManagedIdentityId, '/')[4])
}

// ─── RBAC: Deployment Resource Group (new identity) ─────────────────────────

resource rbacNew 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (roleDefId, i) in roleDefinitions[accessLevel]: if (shouldCreateIdentity) {
  name: guid(resourceGroup().id, newIdentity.id, roleDefId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    principalId: newIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// ─── RBAC: Deployment Resource Group (existing identity) ────────────────────

resource rbacExisting 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (roleDefId, i) in roleDefinitions[accessLevel]: if (!shouldCreateIdentity) {
  name: guid(resourceGroup().id, existingManagedIdentityId, roleDefId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    principalId: existingIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// ─── RBAC: Target Resource Groups ───────────────────────────────────────────

module targetRbacNew 'role-assignments-target.bicep' = [for (targetRG, i) in targetResourceGroups: if (shouldCreateIdentity) {
  name: 'target-rbac-new-${i}-${uniqueString(deployment().name)}'
  scope: resourceGroup(length(targetSubscriptions) > i ? targetSubscriptions[i] : subscriptionId, targetRG)
  params: {
    principalId: newIdentity!.properties.principalId
    accessLevel: accessLevel
  }
}]

module targetRbacExisting 'role-assignments-target.bicep' = [for (targetRG, i) in targetResourceGroups: if (!shouldCreateIdentity) {
  name: 'target-rbac-existing-${i}-${uniqueString(deployment().name)}'
  scope: resourceGroup(length(targetSubscriptions) > i ? targetSubscriptions[i] : subscriptionId, targetRG)
  params: {
    principalId: existingIdentity!.properties.principalId
    accessLevel: accessLevel
  }
}]

// ─── SRE Agent (new identity path) ──────────────────────────────────────────

#disable-next-line BCP081
resource sreAgentNew 'Microsoft.App/agents@2025-05-01-preview' = if (shouldCreateIdentity) {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${newIdentity.id}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: newIdentity.id
      managedResources: []
    }
    actionConfiguration: {
      accessLevel: accessLevel
      identity: newIdentity.id
      mode: agentMode
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: applicationInsights.properties.AppId
        connectionString: applicationInsights.properties.ConnectionString
      }
    }
  }
  dependsOn: [
    rbacNew
    targetRbacNew
  ]
}

// ─── SRE Agent (existing identity path) ─────────────────────────────────────

#disable-next-line BCP081
resource sreAgentExisting 'Microsoft.App/agents@2025-05-01-preview' = if (!shouldCreateIdentity) {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${existingManagedIdentityId}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: existingManagedIdentityId
      managedResources: []
    }
    actionConfiguration: {
      accessLevel: accessLevel
      identity: existingManagedIdentityId
      mode: agentMode
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: applicationInsights.properties.AppId
        connectionString: applicationInsights.properties.ConnectionString
      }
    }
  }
  dependsOn: [
    rbacExisting
    targetRbacExisting
  ]
}

// ─── RBAC: SRE Agent Administrator for deploying user ───────────────────────

resource sreAgentAdminNew 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (shouldCreateIdentity) {
  name: guid(sreAgentNew.id, deployer().objectId, 'e79298df-d852-4c6d-84f9-5d13249d1e55')
  scope: sreAgentNew
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')
    principalId: deployer().objectId
    principalType: 'User'
  }
}

resource sreAgentAdminExisting 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!shouldCreateIdentity) {
  name: guid(sreAgentExisting.id, deployer().objectId, 'e79298df-d852-4c6d-84f9-5d13249d1e55')
  scope: sreAgentExisting
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output agentName string = shouldCreateIdentity ? sreAgentNew!.name : sreAgentExisting!.name
output agentResourceId string = shouldCreateIdentity ? sreAgentNew!.id : sreAgentExisting!.id
output agentEndpoint string = (shouldCreateIdentity ? sreAgentNew!.properties.agentEndpoint : sreAgentExisting!.properties.agentEndpoint) ?? 'pending'
output portalUrl string = 'https://ms.portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/${replace(shouldCreateIdentity ? sreAgentNew!.id : sreAgentExisting!.id, '/', '%2F')}'
output userAssignedIdentityId string = shouldCreateIdentity ? newIdentity!.id : existingManagedIdentityId
output userAssignedIdentityPrincipalId string = shouldCreateIdentity ? newIdentity!.properties.principalId : existingIdentity!.properties.principalId
output applicationInsightsName string = applicationInsights.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
