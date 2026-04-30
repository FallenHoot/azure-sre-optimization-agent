// ============================================================================
// SRE Optimization Engine — Main Bicep Template (Subscription-scoped)
// ============================================================================
// Deploys an Azure SRE Agent with full configuration:
//   - User-Assigned Managed Identity (for knowledge graph + actions)
//   - Log Analytics Workspace + Application Insights (for telemetry)
//   - SRE Agent (API version 2026-01-01) with:
//       knowledgeGraphConfiguration, actionConfiguration, logConfiguration,
//       defaultModel, upgradeChannel
//   - RBAC role assignments (Reader, Monitoring Reader, Log Analytics Reader)
//   - SRE Agent Administrator role for the deploying user
//
// API version: Microsoft.App/agents@2026-01-01
// Subagent YAML format: azuresre.ai/v2 (ExtendedAgent)
//
// Based on the official microsoft/sre-agent Bicep samples:
//   https://github.com/microsoft/sre-agent/tree/main/samples/bicep-deployment
//
// Usage:
//   az deployment sub create \
//     --location swedencentral \
//     --template-file infra/main.bicep \
//     --parameters infra/main.parameters.json
// ============================================================================

targetScope = 'subscription'

// ─── Required Parameters ────────────────────────────────────────────────────

@description('Name of the SRE Agent resource')
param agentName string

@description('Resource group where SRE Agent and supporting resources will be deployed')
param resourceGroupName string

// ─── Optional Parameters ────────────────────────────────────────────────────

@description('Azure region for all resources')
@allowed(['swedencentral', 'eastus2', 'australiaeast', 'uksouth'])
param location string = 'swedencentral'

@description('Subscription ID (defaults to current)')
param subscriptionId string = subscription().subscriptionId

@description('Access level for the SRE Agent managed identity')
@allowed(['High', 'Low'])
param accessLevel string = 'High'

@description('Agent execution mode')
@allowed(['Review', 'Autonomous', 'ReadOnly'])
param agentMode string = 'Review'

@description('Agent upgrade channel')
@allowed(['Stable', 'Preview'])
param upgradeChannel string = 'Stable'

@description('Optional: existing User-Assigned Managed Identity resource ID. If empty, a new one is created.')
param existingManagedIdentityId string = ''

@description('Resource group names the agent should manage (beyond its own RG)')
param targetResourceGroups array = []

@description('Subscription IDs for target resource groups (parallel array, defaults to deployment sub)')
param targetSubscriptions array = []

@description('Tags to apply to all resources')
param tags object = {
  project: 'sre-optimization-engine'
  phase: 'poc'
  SecurityControl: 'Ignore'
}

// ─── Resource Group ─────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ─── Deploy All Resources ───────────────────────────────────────────────────

module sreAgentResources 'modules/sre-agent-resources.bicep' = {
  name: 'sre-agent-resources-${uniqueString(deployment().name)}'
  scope: rg
  params: {
    agentName: agentName
    location: location
    subscriptionId: subscriptionId
    accessLevel: accessLevel
    agentMode: agentMode
    upgradeChannel: upgradeChannel
    existingManagedIdentityId: existingManagedIdentityId
    targetResourceGroups: targetResourceGroups
    targetSubscriptions: targetSubscriptions
    tags: tags
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────

output agentName string = sreAgentResources.outputs.agentName
output agentResourceId string = sreAgentResources.outputs.agentResourceId
output agentEndpoint string = sreAgentResources.outputs.agentEndpoint
output portalUrl string = sreAgentResources.outputs.portalUrl
output userAssignedIdentityId string = sreAgentResources.outputs.userAssignedIdentityId
output userAssignedIdentityPrincipalId string = sreAgentResources.outputs.userAssignedIdentityPrincipalId
output applicationInsightsName string = sreAgentResources.outputs.applicationInsightsName
output logAnalyticsWorkspaceId string = sreAgentResources.outputs.logAnalyticsWorkspaceId
