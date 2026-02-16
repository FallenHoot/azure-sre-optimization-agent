// ============================================================================
// SRE Agent Demo Resources - Resource Group Scoped Module
// ============================================================================
// Deploys all demo resources with intentional optimization opportunities.
// Each resource is designed to trigger specific SRE Agent findings.
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

param location string
param adminUsername string

@secure()
param sshPublicKey string

param nameSuffix string
param tags object

// ============================================================================
// Variables
// ============================================================================

var ubuntuImage = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '22_04-lts-gen2'
  version: 'latest'
}

// ============================================================================
// NETWORKING: VNet + Subnet + NSG
// ============================================================================

// --- NSG with basic rules ---
module nsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-nsg'
  params: {
    name: 'nsg-sre-demo'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          access: 'Allow'
          description: 'Allow SSH for management (demo only)'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          access: 'Deny'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 4096
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

// --- Virtual Network with subnet ---
module vnet 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'deploy-vnet'
  params: {
    name: 'vnet-sre-demo'
    location: location
    tags: tags
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'snet-workloads'
        addressPrefix: '10.0.1.0/24'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
      }
    ]
  }
}

// ============================================================================
// VM1: OVERSIZED OLD-GEN VM
// ============================================================================
// Finding triggers:
//   - Rightsizing: D8s_v3 (8 vCPU / 32 GB) is oversized for a low-util workload
//   - Generation upgrade: v3 → v5 or v6 recommendation
//   - 512 GB Premium OS disk is oversized
//   - Tagged as "production" but low utilization expected
// ============================================================================

module vm1 'br/public:avm/res/compute/virtual-machine:0.12.0' = {
  name: 'deploy-vm1-oversized-oldgen'
  params: {
    name: 'vm-oversized-v3'
    location: location
    tags: union(tags, {
      workload: 'web-frontend'
      environment: 'production'
      'cost-center': 'engineering'
      'optimization-target': 'rightsizing-and-generation-upgrade'
    })
    adminUsername: adminUsername
    zone: 1
    osType: 'Linux'
    vmSize: 'Standard_D8s_v3' // INTENTIONAL: Oversized old-gen SKU
    imageReference: ubuntuImage
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: sshPublicKey
        path: '/home/${adminUsername}/.ssh/authorized_keys'
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 512 // INTENTIONAL: Oversized OS disk
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    dataDisks: [
      {
        caching: 'ReadOnly'
        createOption: 'Empty'
        deleteOption: 'Detach' // INTENTIONAL: Detach on delete = potential orphan
        diskSizeGB: 256
        managedDisk: {
          storageAccountType: 'Premium_LRS' // INTENTIONAL: Premium for low-util
        }
        name: 'vm1-datadisk-01'
      }
    ]
    nicConfigurations: [
      {
        nicSuffix: '-nic-01'
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: vnet.outputs.subnetResourceIds[0]
          }
        ]
      }
    ]
    encryptionAtHost: false
    autoShutdownConfig: {
      status: 'Enabled'
      dailyRecurrenceTime: '1900'
      timeZone: 'W. Europe Standard Time'
      notificationSettings: {
        status: 'Disabled'
      }
    }
  }
}

// ============================================================================
// VM2: DEV/TEST VM - SPOT CANDIDATE
// ============================================================================
// Finding triggers:
//   - Spot eligible: Tagged dev/test, no SLA requirement
//   - Could run as Spot VM with Deallocate eviction policy
//   - Standard_D4s_v5 is appropriately sized but non-Spot
// ============================================================================

module vm2 'br/public:avm/res/compute/virtual-machine:0.12.0' = {
  name: 'deploy-vm2-spot-candidate'
  params: {
    name: 'vm-devtest-nospotv5'
    location: location
    tags: union(tags, {
      workload: 'ci-runner'
      environment: 'development'
      'cost-center': 'devops'
      'sla-required': 'false'
      'optimization-target': 'spot-vm-candidate'
    })
    adminUsername: adminUsername
    zone: 1
    osType: 'Linux'
    vmSize: 'Standard_D4s_v5' // Appropriately sized, current gen
    // INTENTIONAL: NOT using priority: 'Spot' — agent should recommend it
    imageReference: ubuntuImage
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: sshPublicKey
        path: '/home/${adminUsername}/.ssh/authorized_keys'
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic-01'
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: vnet.outputs.subnetResourceIds[0]
          }
        ]
      }
    ]
    encryptionAtHost: false
    autoShutdownConfig: {
      status: 'Enabled'
      dailyRecurrenceTime: '1900'
      timeZone: 'W. Europe Standard Time'
      notificationSettings: {
        status: 'Disabled'
      }
    }
  }
}

// ============================================================================
// VM3: NO AVAILABILITY ZONE
// ============================================================================
// Finding triggers:
//   - HA gap: No availability zone set (zone -1)
//   - Old generation: D2s_v3 → upgrade to v5
//   - Tagged as staging but still needs HA recommendation
// ============================================================================

module vm3 'br/public:avm/res/compute/virtual-machine:0.12.0' = {
  name: 'deploy-vm3-no-zone'
  params: {
    name: 'vm-nozone-staging'
    location: location
    tags: union(tags, {
      workload: 'api-backend'
      environment: 'staging'
      'cost-center': 'engineering'
      'optimization-target': 'availability-zone-and-gen-upgrade'
    })
    adminUsername: adminUsername
    zone: 0 // INTENTIONAL: No zone = HA gap
    osType: 'Linux'
    vmSize: 'Standard_D2s_v3' // INTENTIONAL: Old gen v3
    imageReference: ubuntuImage
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: sshPublicKey
        path: '/home/${adminUsername}/.ssh/authorized_keys'
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'StandardSSD_LRS'
      }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic-01'
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: vnet.outputs.subnetResourceIds[0]
          }
        ]
      }
    ]
    encryptionAtHost: false
    autoShutdownConfig: {
      status: 'Enabled'
      dailyRecurrenceTime: '1900'
      timeZone: 'W. Europe Standard Time'
      notificationSettings: {
        status: 'Disabled'
      }
    }
  }
}

// ============================================================================
// STANDALONE DISKS (UNATTACHED / ORPHANED)
// ============================================================================
// Finding triggers:
//   - Unattached Premium_LRS disk → orphan cleanup / cost waste
//   - Unattached StandardSSD_LRS disk → orphan cleanup
//   - Large unattached disk (1 TB) → high cost waste
// ============================================================================

module orphanDisk1 'br/public:avm/res/compute/disk:0.4.1' = {
  name: 'deploy-orphan-disk-premium'
  params: {
    name: 'disk-orphan-premium-512'
    location: location
    tags: union(tags, {
      'optimization-target': 'unattached-disk-cleanup'
      'original-vm': 'vm-decommissioned-app01'
    })
    availabilityZone: 0
    sku: 'Premium_LRS' // INTENTIONAL: Premium disk sitting unattached
    diskSizeGB: 512 // INTENTIONAL: Large disk = more cost waste
    createOption: 'Empty'
  }
}

module orphanDisk2 'br/public:avm/res/compute/disk:0.4.1' = {
  name: 'deploy-orphan-disk-standard'
  params: {
    name: 'disk-orphan-std-1024'
    location: location
    tags: union(tags, {
      'optimization-target': 'unattached-disk-cleanup'
      'original-vm': 'vm-decommissioned-db01'
    })
    availabilityZone: 0
    sku: 'StandardSSD_LRS'
    diskSizeGB: 1024 // INTENTIONAL: 1 TB unattached disk
    createOption: 'Empty'
  }
}

// ============================================================================
// STORAGE ACCOUNT 1: HOT TIER WITHOUT LIFECYCLE POLICY
// ============================================================================
// Finding triggers:
//   - Hot access tier with no lifecycle management policy
//   - Should move to Cool/Archive for infrequently accessed data
//   - Agent should recommend adding lifecycle policy rules
// ============================================================================

module storageHot 'br/public:avm/res/storage/storage-account:0.14.3' = {
  name: 'deploy-storage-hot-no-lifecycle'
  params: {
    name: 'st${nameSuffix}hotnolc'
    location: location
    tags: union(tags, {
      'data-classification': 'internal'
      'optimization-target': 'lifecycle-policy-missing'
    })
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    accessTier: 'Hot' // INTENTIONAL: Hot tier without lifecycle = cost waste
    // INTENTIONAL: No managementPolicyRules = no lifecycle policy
    blobServices: {
      containers: [
        {
          name: 'logs'
          publicAccess: 'None'
        }
        {
          name: 'backups'
          publicAccess: 'None'
        }
        {
          name: 'archives'
          publicAccess: 'None'
        }
      ]
    }
    networkAcls: {
      defaultAction: 'Allow' // INTENTIONAL: Open network = security finding
    }
  }
}

// ============================================================================
// STORAGE ACCOUNT 2: WITH LIFECYCLE POLICY (BASELINE)
// ============================================================================
// Purpose: Well-configured storage account for comparison
//   - Has lifecycle management policy
//   - Cool tier for archival data
//   - Agent should find this well-configured (no findings or fewer findings)
// ============================================================================

module storageLifecycle 'br/public:avm/res/storage/storage-account:0.14.3' = {
  name: 'deploy-storage-with-lifecycle'
  params: {
    name: 'st${nameSuffix}lifecycle'
    location: location
    tags: union(tags, {
      'data-classification': 'internal'
      'optimization-target': 'baseline-well-configured'
    })
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    accessTier: 'Cool' // Appropriate for archival data
    blobServices: {
      containers: [
        {
          name: 'data'
          publicAccess: 'None'
        }
      ]
    }
    managementPolicyRules: [
      {
        enabled: true
        name: 'move-to-cool-after-30-days'
        type: 'Lifecycle'
        definition: {
          actions: {
            baseBlob: {
              tierToCool: {
                daysAfterModificationGreaterThan: 30
              }
              tierToArchive: {
                daysAfterModificationGreaterThan: 90
              }
              delete: {
                daysAfterModificationGreaterThan: 365
              }
            }
            snapshot: {
              delete: {
                daysAfterCreationGreaterThan: 90
              }
            }
          }
          filters: {
            blobTypes: [
              'blockBlob'
            ]
          }
        }
      }
    ]
    networkAcls: {
      defaultAction: 'Deny' // Properly restricted
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

output vnetName string = vnet.outputs.name
output vm1Name string = vm1.outputs.name
output vm2Name string = vm2.outputs.name
output vm3Name string = vm3.outputs.name
output storageAccountHotName string = storageHot.outputs.name
output storageAccountLifecycleName string = storageLifecycle.outputs.name
output orphanDisk1Name string = orphanDisk1.outputs.name
output orphanDisk2Name string = orphanDisk2.outputs.name
