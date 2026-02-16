# Azure Resource Graph Queries

## Purpose

This document provides pre-built Azure Resource Graph (ARG) queries for every resource type that the optimization subagents need to inventory. These queries are the starting point for each scan — they identify the resources to analyze before metrics and pricing data are collected.

---

## General Notes

### Pagination

ARG queries return a maximum of 1,000 results per page. Use `--first` and `--skip` for pagination:

```bash
az graph query -q "<QUERY>" --first 1000 --skip 0
az graph query -q "<QUERY>" --first 1000 --skip 1000
az graph query -q "<QUERY>" --first 1000 --skip 2000
# Continue until fewer than 1000 results are returned
```

### Cross-Subscription Queries

To query across multiple subscriptions:

```bash
az graph query -q "<QUERY>" --subscriptions sub-id-1 sub-id-2 sub-id-3
```

Or query all subscriptions the identity has access to (omit `--subscriptions`).

### Useful Operators

- `project` — select specific columns
- `extend` — add computed columns
- `where` — filter rows
- `mv-expand` — expand arrays into rows
- `summarize` — aggregate
- `join` — join tables
- `order by` — sort results

---

## 1. Virtual Machines

### All VMs with Properties

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend
    vmSize = tostring(properties.hardwareProfile.vmSize),
    powerState = tostring(properties.extended.instanceView.powerState.code),
    osType = tostring(properties.storageProfile.osDisk.osType),
    osDiskSku = tostring(properties.storageProfile.osDisk.managedDisk.storageAccountType),
    osDiskSizeGB = toint(properties.storageProfile.osDisk.diskSizeGB),
    dataDisks = array_length(properties.storageProfile.dataDisks),
    nicCount = array_length(properties.networkProfile.networkInterfaces),
    availabilitySet = tostring(properties.availabilitySet.id),
    zones = properties.zones,
    priority = tostring(properties.priority),
    licenseType = tostring(properties.licenseType),
    provisioningState = tostring(properties.provisioningState)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    vmSize,
    powerState,
    osType,
    osDiskSku,
    osDiskSizeGB,
    dataDisks,
    nicCount,
    availabilitySet,
    zones,
    priority,
    licenseType,
    provisioningState,
    tags
| order by subscriptionId asc, resourceGroup asc, name asc
```

**CLI command:**
```bash
az graph query -q "Resources | where type =~ 'microsoft.compute/virtualmachines' | extend vmSize = tostring(properties.hardwareProfile.vmSize), powerState = tostring(properties.extended.instanceView.powerState.code), osType = tostring(properties.storageProfile.osDisk.osType), dataDisks = array_length(properties.storageProfile.dataDisks), nicCount = array_length(properties.networkProfile.networkInterfaces), availabilitySet = tostring(properties.availabilitySet.id), zones = properties.zones | project id, name, resourceGroup, subscriptionId, location, vmSize, powerState, osType, dataDisks, nicCount, availabilitySet, zones, tags" --first 1000
```

### Stopped-Not-Deallocated VMs (Critical Finding)

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend powerState = tostring(properties.extended.instanceView.powerState.code)
| where powerState == 'PowerState/stopped'
| project id, name, resourceGroup, subscriptionId, location,
    vmSize = tostring(properties.hardwareProfile.vmSize),
    osType = tostring(properties.storageProfile.osDisk.osType),
    tags
```

### Deallocated VMs

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend powerState = tostring(properties.extended.instanceView.powerState.code)
| where powerState == 'PowerState/deallocated'
| project id, name, resourceGroup, subscriptionId, location,
    vmSize = tostring(properties.hardwareProfile.vmSize),
    tags
```

> **Note:** ARG does not store the deallocation timestamp. Use Activity Log queries to determine when the VM was deallocated.

### VMs Without High Availability (No Availability Zone or Set)

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend powerState = tostring(properties.extended.instanceView.powerState.code)
| where powerState == 'PowerState/running'
| where isnull(properties.availabilitySet) and array_length(zones) == 0
| project id, name, resourceGroup, subscriptionId, location,
    vmSize = tostring(properties.hardwareProfile.vmSize),
    osType = tostring(properties.storageProfile.osDisk.osType),
    tags
```

**CLI command:**
```bash
az graph query -q "Resources | where type =~ 'microsoft.compute/virtualmachines' | extend powerState = tostring(properties.extended.instanceView.powerState.code) | where powerState == 'PowerState/running' | where isnull(properties.availabilitySet) and array_length(zones) == 0 | project id, name, resourceGroup, subscriptionId, location, vmSize = tostring(properties.hardwareProfile.vmSize), tags" --first 1000 --subscription <subscription-id>
```

---

## 2. Virtual Machine Scale Sets (VMSS)

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachinescalesets'
| extend
    vmSize = tostring(properties.virtualMachineProfile.hardwareProfile.vmSize),
    capacity = toint(sku.capacity),
    skuName = tostring(sku.name),
    skuTier = tostring(sku.tier),
    upgradePolicy = tostring(properties.upgradePolicy.mode),
    overprovision = tostring(properties.overprovision),
    singlePlacementGroup = tostring(properties.singlePlacementGroup),
    zones = properties.zones
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    vmSize,
    capacity,
    skuName,
    skuTier,
    upgradePolicy,
    overprovision,
    singlePlacementGroup,
    zones,
    tags
| order by subscriptionId asc, resourceGroup asc, name asc
```

---

## 3. Managed Disks

### All Managed Disks (with Unattached Detection)

```kql
Resources
| where type =~ 'microsoft.compute/disks'
| extend
    diskState = tostring(properties.diskState),
    diskSku = tostring(sku.name),
    diskTier = tostring(sku.tier),
    diskSizeGB = toint(properties.diskSizeGB),
    diskIOPSReadWrite = toint(properties.diskIOPSReadWrite),
    diskMBpsReadWrite = toint(properties.diskMBpsReadWrite),
    managedBy = tostring(properties.managedBy),
    timeCreated = tostring(properties.timeCreated),
    osType = tostring(properties.osType),
    isUnattached = isnull(properties.managedBy) or properties.managedBy == ''
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    diskState,
    diskSku,
    diskTier,
    diskSizeGB,
    diskIOPSReadWrite,
    diskMBpsReadWrite,
    managedBy,
    timeCreated,
    osType,
    isUnattached,
    tags
| order by isUnattached desc, diskSizeGB desc
```

### Unattached Disks Only

```kql
Resources
| where type =~ 'microsoft.compute/disks'
| where isnull(properties.managedBy) or tostring(properties.managedBy) == ''
| extend
    diskSku = tostring(sku.name),
    diskSizeGB = toint(properties.diskSizeGB),
    diskIOPSReadWrite = toint(properties.diskIOPSReadWrite),
    timeCreated = tostring(properties.timeCreated)
| project id, name, resourceGroup, subscriptionId, location,
    diskSku, diskSizeGB, diskIOPSReadWrite, timeCreated, tags
| order by diskSizeGB desc
```

---

## 4. Snapshots

```kql
Resources
| where type =~ 'microsoft.compute/snapshots'
| extend
    diskSizeGB = toint(properties.diskSizeGB),
    timeCreated = tostring(properties.timeCreated),
    sourceResourceId = tostring(properties.creationData.sourceResourceId),
    snapshotSku = tostring(sku.name)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    diskSizeGB,
    timeCreated,
    sourceResourceId,
    snapshotSku,
    tags
| order by timeCreated asc
```

---

## 5. Load Balancers

### All Load Balancers with Backend Pool Count

```kql
Resources
| where type =~ 'microsoft.network/loadbalancers'
| extend
    skuName = tostring(sku.name),
    skuTier = tostring(sku.tier),
    backendPoolCount = array_length(properties.backendAddressPools),
    frontendIPCount = array_length(properties.frontendIPConfigurations),
    loadBalancingRuleCount = array_length(properties.loadBalancingRules),
    probeCount = array_length(properties.probes)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    skuName,
    skuTier,
    backendPoolCount,
    frontendIPCount,
    loadBalancingRuleCount,
    probeCount,
    tags
| order by backendPoolCount asc
```

### Unused Load Balancers (Zero Backend Pools or Empty Pools)

```kql
Resources
| where type =~ 'microsoft.network/loadbalancers'
| where array_length(properties.backendAddressPools) == 0
    or properties.backendAddressPools[0].properties.loadBalancerBackendAddresses == dynamic([])
| extend skuName = tostring(sku.name)
| project id, name, resourceGroup, subscriptionId, location, skuName, tags
```

---

## 6. Application Gateways

```kql
Resources
| where type =~ 'microsoft.network/applicationgateways'
| extend
    skuName = tostring(properties.sku.name),
    skuTier = tostring(properties.sku.tier),
    capacity = toint(properties.sku.capacity),
    backendPoolCount = array_length(properties.backendAddressPools),
    backendPoolTargets = array_length(properties.backendAddressPools[0].properties.backendAddresses),
    httpListenerCount = array_length(properties.httpListeners),
    ruleCount = array_length(properties.requestRoutingRules)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    skuName,
    skuTier,
    capacity,
    backendPoolCount,
    backendPoolTargets,
    httpListenerCount,
    ruleCount,
    tags
| order by backendPoolTargets asc
```

---

## 7. Network Security Groups (NSGs)

```kql
Resources
| where type =~ 'microsoft.network/networksecuritygroups'
| extend
    customRuleCount = array_length(properties.securityRules),
    subnetCount = array_length(properties.subnets),
    nicCount = array_length(properties.networkInterfaces),
    subnetIds = properties.subnets,
    nicIds = properties.networkInterfaces
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    customRuleCount,
    subnetCount,
    nicCount,
    tags
| order by customRuleCount asc
```

### NSGs with No Associations

```kql
Resources
| where type =~ 'microsoft.network/networksecuritygroups'
| where isnull(properties.subnets) or array_length(properties.subnets) == 0
| where isnull(properties.networkInterfaces) or array_length(properties.networkInterfaces) == 0
| project id, name, resourceGroup, subscriptionId, location, tags
```

---

## 8. Public IP Addresses

```kql
Resources
| where type =~ 'microsoft.network/publicipaddresses'
| extend
    ipAddress = tostring(properties.ipAddress),
    publicIPAllocationMethod = tostring(properties.publicIPAllocationMethod),
    skuName = tostring(sku.name),
    associatedResourceId = tostring(properties.ipConfiguration.id),
    isAssociated = isnotnull(properties.ipConfiguration),
    dnsLabel = tostring(properties.dnsSettings.domainNameLabel)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    ipAddress,
    publicIPAllocationMethod,
    skuName,
    associatedResourceId,
    isAssociated,
    dnsLabel,
    tags
| order by isAssociated asc
```

### Unassociated Public IPs

```kql
Resources
| where type =~ 'microsoft.network/publicipaddresses'
| where isnull(properties.ipConfiguration)
| extend
    skuName = tostring(sku.name),
    publicIPAllocationMethod = tostring(properties.publicIPAllocationMethod)
| project id, name, resourceGroup, subscriptionId, location,
    skuName, publicIPAllocationMethod, tags
```

---

## 9. Virtual Networks and Subnets

```kql
Resources
| where type =~ 'microsoft.network/virtualnetworks'
| extend
    addressPrefixes = properties.addressSpace.addressPrefixes,
    subnetCount = array_length(properties.subnets),
    peeringCount = array_length(properties.virtualNetworkPeerings),
    enableDdosProtection = tostring(properties.enableDdosProtection)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    addressPrefixes,
    subnetCount,
    peeringCount,
    enableDdosProtection,
    tags
| order by subscriptionId asc, resourceGroup asc, name asc
```

### Subnets with Connected Device Count

```kql
Resources
| where type =~ 'microsoft.network/virtualnetworks'
| mv-expand subnet = properties.subnets
| extend
    subnetName = tostring(subnet.name),
    subnetPrefix = tostring(subnet.properties.addressPrefix),
    connectedDevices = array_length(subnet.properties.ipConfigurations),
    nsgId = tostring(subnet.properties.networkSecurityGroup.id),
    routeTableId = tostring(subnet.properties.routeTable.id)
| project
    vnetId = id,
    vnetName = name,
    resourceGroup,
    subscriptionId,
    location,
    subnetName,
    subnetPrefix,
    connectedDevices,
    nsgId,
    routeTableId
| order by connectedDevices asc
```

---

## 10. App Service Plans

```kql
Resources
| where type =~ 'microsoft.web/serverfarms'
| extend
    skuName = tostring(sku.name),
    skuTier = tostring(sku.tier),
    skuSize = tostring(sku.size),
    skuFamily = tostring(sku.family),
    workerCount = toint(properties.numberOfWorkers),
    maxWorkers = toint(properties.maximumNumberOfWorkers),
    appCount = toint(properties.numberOfSites),
    status = tostring(properties.status),
    reserved = tostring(properties.reserved),
    isLinux = tostring(properties.reserved),
    kind = tostring(kind)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    skuName,
    skuTier,
    skuSize,
    workerCount,
    maxWorkers,
    appCount,
    status,
    isLinux,
    kind,
    tags
| order by appCount asc
```

### Empty App Service Plans

```kql
Resources
| where type =~ 'microsoft.web/serverfarms'
| where toint(properties.numberOfSites) == 0
| extend
    skuName = tostring(sku.name),
    skuTier = tostring(sku.tier)
| project id, name, resourceGroup, subscriptionId, location,
    skuName, skuTier, tags
```

---

## 11. SQL Databases

```kql
Resources
| where type =~ 'microsoft.sql/servers/databases'
| where name != 'master'
| extend
    skuName = tostring(sku.name),
    skuTier = tostring(sku.tier),
    skuCapacity = toint(sku.capacity),
    maxSizeGB = todouble(properties.maxSizeBytes) / 1073741824,
    collation = tostring(properties.collation),
    status = tostring(properties.status),
    elasticPoolId = tostring(properties.elasticPoolId),
    isInElasticPool = isnotnull(properties.elasticPoolId) and tostring(properties.elasticPoolId) != '',
    zoneRedundant = tostring(properties.zoneRedundant),
    currentServiceObjectiveName = tostring(properties.currentServiceObjectiveName),
    requestedServiceObjectiveName = tostring(properties.requestedServiceObjectiveName)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    skuName,
    skuTier,
    skuCapacity,
    maxSizeGB,
    status,
    elasticPoolId,
    isInElasticPool,
    zoneRedundant,
    currentServiceObjectiveName,
    tags
| order by subscriptionId asc, resourceGroup asc, name asc
```

---

## 12. Storage Accounts

```kql
Resources
| where type =~ 'microsoft.storage/storageaccounts'
| extend
    skuName = tostring(sku.name),
    skuTier = tostring(sku.tier),
    kind = tostring(kind),
    accessTier = tostring(properties.accessTier),
    supportsHttpsTrafficOnly = tostring(properties.supportsHttpsTrafficOnly),
    minimumTlsVersion = tostring(properties.minimumTlsVersion),
    allowBlobPublicAccess = tostring(properties.allowBlobPublicAccess),
    networkRuleSetDefaultAction = tostring(properties.networkAcls.defaultAction),
    isHnsEnabled = tostring(properties.isHnsEnabled),
    creationTime = tostring(properties.creationTime)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    skuName,
    skuTier,
    kind,
    accessTier,
    supportsHttpsTrafficOnly,
    minimumTlsVersion,
    allowBlobPublicAccess,
    networkRuleSetDefaultAction,
    isHnsEnabled,
    creationTime,
    tags
| order by subscriptionId asc, resourceGroup asc, name asc
```

> **Note:** Lifecycle policy status is not available in ARG. Use ARM API call `GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}/managementPolicies/default` to check.

---

## 13. NAT Gateways

```kql
Resources
| where type =~ 'microsoft.network/natgateways'
| extend
    skuName = tostring(sku.name),
    idleTimeoutInMinutes = toint(properties.idleTimeoutInMinutes),
    subnetCount = array_length(properties.subnets),
    publicIpCount = array_length(properties.publicIpAddresses),
    publicIpPrefixCount = array_length(properties.publicIpPrefixes)
| project
    id,
    name,
    resourceGroup,
    subscriptionId,
    location,
    skuName,
    idleTimeoutInMinutes,
    subnetCount,
    publicIpCount,
    publicIpPrefixCount,
    tags
| order by subnetCount asc
```

### Unused NAT Gateways (No Subnet Associations)

```kql
Resources
| where type =~ 'microsoft.network/natgateways'
| where isnull(properties.subnets) or array_length(properties.subnets) == 0
| project id, name, resourceGroup, subscriptionId, location, tags
```

---

## 14. Resource Containers

### All Subscriptions

```kql
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions'
| project
    subscriptionId,
    name,
    state = tostring(properties.state),
    displayName = tostring(properties.displayName)
| order by name asc
```

### All Resource Groups

```kql
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions/resourcegroups'
| project
    id,
    name,
    subscriptionId,
    location,
    tags
| order by subscriptionId asc, name asc
```

---

## Query Execution Best Practices

1. **Always paginate** — never assume results fit in one page
2. **Use `project`** — only return needed columns to reduce response size
3. **Use `where` early** — filter before extending to reduce processing
4. **Cache results** — ARG results for a single scan run can be cached; resources don't change that fast
5. **Handle throttling** — ARG has rate limits; implement exponential backoff on HTTP 429
6. **Subscription scope** — always specify subscriptions when possible to improve performance
7. **Test queries** — validate in Azure Portal Resource Graph Explorer before deploying
