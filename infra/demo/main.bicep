// ============================================================================
// SRE Agent Optimization Engine - Demo Environment
// ============================================================================
// Purpose: Deploy intentionally misconfigured Azure resources to demonstrate
//          SRE Agent optimization findings across compute, storage, and network.
//
// Resources deployed (all with deliberate optimization opportunities):
//   - VNet + Subnet + NSG (networking foundation)
//   - VM1: Oversized old-gen VM (D8s_v3) → rightsizing + generation upgrade
//   - VM2: Dev/test VM without Spot → Spot recommendation
//   - VM3: VM without availability zone → HA gap finding
//   - Standalone Premium disks (unattached) → orphan cleanup
//   - Storage account on Hot tier without lifecycle → lifecycle policy
//   - Storage account with lifecycle policy (baseline comparison)
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Location for all demo resources.')
@allowed([
  'swedencentral'
  'eastus2'
  'australiaeast'
  'uksouth'
])
param location string = 'swedencentral'

@description('Resource group name for demo resources.')
param resourceGroupName string = 'rg-sre-demo-workloads'

@description('Admin username for Linux VMs.')
param adminUsername string = 'azureuser'

@description('SSH public key for Linux VM authentication.')
@secure()
param sshPublicKey string

@description('Unique suffix for globally unique resource names.')
param nameSuffix string = 'sredemo'

// ============================================================================
// Variables
// ============================================================================

var tags = {
  project: 'sre-optimization-engine'
  phase: 'demo'
  purpose: 'optimization-findings-demo'
  'managed-by': 'bicep'
}

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Module: Demo Resources
// ============================================================================

module demoResources 'modules/demo-resources.bicep' = {
  name: 'deploy-demo-resources'
  scope: rg
  params: {
    location: location
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    nameSuffix: nameSuffix
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

output resourceGroupName string = rg.name
output resourceGroupId string = rg.id
output vnetName string = demoResources.outputs.vnetName
output vm1Name string = demoResources.outputs.vm1Name
output vm2Name string = demoResources.outputs.vm2Name
output vm3Name string = demoResources.outputs.vm3Name
output storageAccountHotName string = demoResources.outputs.storageAccountHotName
output storageAccountLifecycleName string = demoResources.outputs.storageAccountLifecycleName
output orphanDisk1Name string = demoResources.outputs.orphanDisk1Name
output orphanDisk2Name string = demoResources.outputs.orphanDisk2Name
