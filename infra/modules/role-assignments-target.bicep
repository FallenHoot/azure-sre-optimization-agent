// ============================================================================
// Role Assignments for Target Resource Groups
// ============================================================================
// Assigns RBAC roles to the SRE Agent's User-Assigned Managed Identity
// on resource groups outside the deployment RG.

@description('Principal ID of the User-Assigned Managed Identity')
param principalId string

@description('Access level determines which roles are assigned')
@allowed(['High', 'Low'])
param accessLevel string

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

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (roleDefId, i) in roleDefinitions[accessLevel]: {
  name: guid(resourceGroup().id, principalId, roleDefId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]

output assignedRoles array = [for (roleDefId, i) in roleDefinitions[accessLevel]: {
  roleDefinitionId: roleDefId
  principalId: principalId
  resourceGroupId: resourceGroup().id
}]
