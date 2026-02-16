# Azure Monitor Metric Collection Guide

## Purpose

This document specifies which Azure Monitor metrics to query for each resource type, the time grains and aggregations to use, and complete KQL query patterns. Accurate metric collection is the foundation of all optimization recommendations — without good metric data, rightsizing recommendations are unreliable.

---

## Metric Collection Architecture

There are two primary ways to collect Azure Monitor metrics:

| Method | Source | Best For | P99 Support | Prerequisites |
|---|---|---|---|---|
| **KQL via Log Analytics** | `Perf` table, `InsightsMetrics` table | Complex aggregations, P99 calculations, historical analysis | ✅ Native via `percentile()` | Azure Monitor Agent (AMA) or Log Analytics Agent, VM Insights |
| **Azure Monitor Metrics API** | Platform metrics | Simple queries, real-time data, no agent required | ❌ No native P99; use Maximum as approximation | None for platform metrics |

### Recommendation

**Prefer KQL via Log Analytics** when available, because:
- Native P99 (percentile) aggregation support
- Richer time-series analysis capabilities
- Cross-resource queries in a single workspace
- Historical data retention (configurable, typically 30–90 days)

**Fall back to Metrics API** when:
- VM Insights / AMA is not deployed
- Only platform metrics are needed (e.g., App Service, SQL DB)
- Real-time data is needed

---

## Prerequisites and Agent Requirements

### Metrics Available WITHOUT Any Agent

These platform metrics are available for all VMs automatically:

| Metric | Available | Notes |
|---|---|---|
| CPU Percentage | ✅ | Platform metric, always available |
| Network In/Out | ✅ | Platform metric, always available |
| Disk Read/Write Bytes | ✅ | Platform metric, always available |
| Disk Read/Write Operations/Sec | ✅ | Platform metric, always available |
| **Memory** | ❌ | **Requires agent** |

### Metrics Requiring Azure Monitor Agent (AMA) or VM Insights

| Metric | Requires | Table |
|---|---|---|
| Memory utilization % | AMA + VM Insights | `InsightsMetrics` |
| Disk IOPS (detailed) | AMA | `Perf` |
| Disk throughput (detailed) | AMA | `Perf` |
| Logical disk free space | AMA | `Perf` |
| Network interface throughput | AMA | `Perf` |

### Data Quality Classification

Based on available metrics, classify data quality:

| Quality Level | Criteria |
|---|---|
| **Full** | CPU + Memory + Disk IOPS + Disk Throughput + Network — all available for full lookback period |
| **Partial** | CPU available, but missing memory or disk detail metrics |
| **Minimal** | Only platform metrics (CPU, basic network I/O) |
| **None** | No metric data at all (VM may be off, or not sending data) |

---

## KQL Queries for VM Metrics

### Default Parameters

```
Lookback Period: 7 days (configurable to 30 or 90)
Time Grain: 1 hour (PT1H)
Aggregation: P99 (99th percentile)
```

### CPU Utilization — P99 (7 Days)

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize cpuP99 = percentile(CounterValue, 99) by Computer, bin(TimeGenerated, 1h)
| summarize overallCpuP99 = percentile(cpuP99, 99) by Computer
| order by overallCpuP99 asc
```

**Alternative using InsightsMetrics (VM Insights):**

```kql
InsightsMetrics
| where TimeGenerated > ago(7d)
| where Namespace == "Processor" and Name == "UtilizationPercentage"
| extend Computer = tostring(todynamic(Tags)["vm.azm.ms/computer"])
| summarize cpuP99 = percentile(Val, 99) by Computer, bin(TimeGenerated, 1h)
| summarize overallCpuP99 = percentile(cpuP99, 99) by Computer
| order by overallCpuP99 asc
```

### Memory Utilization — P99 (7 Days)

> **Requires:** Azure Monitor Agent + VM Insights

```kql
InsightsMetrics
| where TimeGenerated > ago(7d)
| where Namespace == "Memory" and Name == "AvailableMB"
| extend Computer = tostring(todynamic(Tags)["vm.azm.ms/computer"])
| extend totalMemoryMB = todouble(todynamic(Tags)["vm.azm.ms/totalMemoryMB"])
| extend memoryUsedPct = 100 - (Val / totalMemoryMB * 100)
| summarize memP99 = percentile(memoryUsedPct, 99) by Computer, bin(TimeGenerated, 1h)
| summarize overallMemP99 = percentile(memP99, 99) by Computer
| order by overallMemP99 asc
```

**Alternative using Perf table (Linux):**

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Memory" and CounterName == "% Used Memory"
| summarize memP99 = percentile(CounterValue, 99) by Computer, bin(TimeGenerated, 1h)
| summarize overallMemP99 = percentile(memP99, 99) by Computer
| order by overallMemP99 asc
```

**Alternative using Perf table (Windows):**

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Memory" and CounterName == "% Committed Bytes In Use"
| summarize memP99 = percentile(CounterValue, 99) by Computer, bin(TimeGenerated, 1h)
| summarize overallMemP99 = percentile(memP99, 99) by Computer
| order by overallMemP99 asc
```

### Disk Read IOPS — P99 (7 Days)

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "LogicalDisk" and CounterName == "Disk Reads/sec"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| summarize iopsP99 = percentile(CounterValue, 99) by Computer, InstanceName, bin(TimeGenerated, 1h)
| summarize overallReadIOPSP99 = percentile(iopsP99, 99) by Computer, InstanceName
| order by overallReadIOPSP99 desc
```

### Disk Write IOPS — P99 (7 Days)

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "LogicalDisk" and CounterName == "Disk Writes/sec"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| summarize iopsP99 = percentile(CounterValue, 99) by Computer, InstanceName, bin(TimeGenerated, 1h)
| summarize overallWriteIOPSP99 = percentile(iopsP99, 99) by Computer, InstanceName
| order by overallWriteIOPSP99 desc
```

### Disk Read Throughput — P99 (7 Days)

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "LogicalDisk" and CounterName == "Disk Read Bytes/sec"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| extend throughputMBps = CounterValue / 1048576.0
| summarize throughputP99 = percentile(throughputMBps, 99) by Computer, InstanceName, bin(TimeGenerated, 1h)
| summarize overallReadThroughputP99 = percentile(throughputP99, 99) by Computer, InstanceName
| order by overallReadThroughputP99 desc
```

### Disk Write Throughput — P99 (7 Days)

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "LogicalDisk" and CounterName == "Disk Write Bytes/sec"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| extend throughputMBps = CounterValue / 1048576.0
| summarize throughputP99 = percentile(throughputMBps, 99) by Computer, InstanceName, bin(TimeGenerated, 1h)
| summarize overallWriteThroughputP99 = percentile(throughputP99, 99) by Computer, InstanceName
| order by overallWriteThroughputP99 desc
```

### Network Throughput — P99 (7 Days)

```kql
Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Network Adapter" and CounterName == "Bytes Total/sec"
| where InstanceName !contains "isatap" and InstanceName !contains "Loopback"
| extend throughputMbps = CounterValue * 8 / 1000000.0
| summarize netP99 = percentile(throughputMbps, 99) by Computer, bin(TimeGenerated, 1h)
| summarize overallNetP99 = percentile(netP99, 99) by Computer
| order by overallNetP99 desc
```

---

## Comprehensive VM Metrics Query (All-in-One)

This query collects all key metrics for all VMs in a single pass:

```kql
let lookback = 7d;
let cpuData = Perf
    | where TimeGenerated > ago(lookback)
    | where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
    | summarize cpuP99 = percentile(CounterValue, 99) by Computer;
let memData = InsightsMetrics
    | where TimeGenerated > ago(lookback)
    | where Namespace == "Memory" and Name == "AvailableMB"
    | extend Computer = tostring(todynamic(Tags)["vm.azm.ms/computer"])
    | extend totalMemoryMB = todouble(todynamic(Tags)["vm.azm.ms/totalMemoryMB"])
    | extend memoryUsedPct = 100 - (Val / totalMemoryMB * 100)
    | summarize memP99 = percentile(memoryUsedPct, 99) by Computer;
let diskIOPS = Perf
    | where TimeGenerated > ago(lookback)
    | where ObjectName == "LogicalDisk" and CounterName in ("Disk Reads/sec", "Disk Writes/sec")
    | where InstanceName !in ("_Total", "HarddiskVolume1")
    | summarize totalIOPS = percentile(CounterValue, 99) by Computer;
let netData = Perf
    | where TimeGenerated > ago(lookback)
    | where ObjectName == "Network Adapter" and CounterName == "Bytes Total/sec"
    | where InstanceName !contains "isatap" and InstanceName !contains "Loopback"
    | extend throughputMbps = CounterValue * 8 / 1000000.0
    | summarize netP99Mbps = percentile(throughputMbps, 99) by Computer;
cpuData
| join kind=leftouter memData on Computer
| join kind=leftouter diskIOPS on Computer
| join kind=leftouter netData on Computer
| project Computer, cpuP99, memP99, totalIOPS, netP99Mbps
| order by cpuP99 asc
```

---

## Azure Monitor Metrics API (Fallback)

When KQL/Log Analytics is not available, use the Azure Monitor Metrics API:

### CLI Commands

**CPU Percentage (Maximum aggregation over 7 days, 1-hour grain):**

```bash
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{vmName}" \
  --metric "Percentage CPU" \
  --start-time "2026-02-06T00:00:00Z" \
  --end-time "2026-02-13T00:00:00Z" \
  --interval PT1H \
  --aggregation Maximum \
  --output json
```

**Network In Total (bytes):**

```bash
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{vmName}" \
  --metric "Network In Total" \
  --start-time "2026-02-06T00:00:00Z" \
  --end-time "2026-02-13T00:00:00Z" \
  --interval PT1H \
  --aggregation Maximum \
  --output json
```

**Disk Read Operations/Sec:**

```bash
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{vmName}" \
  --metric "Disk Read Operations/Sec" \
  --start-time "2026-02-06T00:00:00Z" \
  --end-time "2026-02-13T00:00:00Z" \
  --interval PT1H \
  --aggregation Maximum \
  --output json
```

> **Note:** The Metrics API does not support P99 aggregation natively. Use `Maximum` as an approximation, but note that it will be more conservative (higher) than P99. Prefer KQL for accurate P99 calculations.

---

## PaaS Metrics

### App Service Metrics

Queried via Azure Monitor Metrics API (platform metrics, no agent needed):

| Metric Name | API Metric | Aggregation | Notes |
|---|---|---|---|
| CPU Percentage | `CpuPercentage` | Maximum / Average | Per App Service Plan |
| Memory Percentage | `MemoryPercentage` | Maximum / Average | Per App Service Plan |
| Disk Queue Length | `DiskQueueLength` | Maximum | Indicates disk pressure |
| HTTP Queue Length | `HttpQueueLength` | Maximum | Indicates request queuing |
| Requests | `Requests` | Total | Request volume |
| Response Time | `HttpResponseTime` | Average / P95 | Latency |

```bash
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/serverFarms/{planName}" \
  --metric "CpuPercentage" "MemoryPercentage" \
  --start-time "2026-02-06T00:00:00Z" \
  --end-time "2026-02-13T00:00:00Z" \
  --interval PT1H \
  --aggregation Maximum \
  --output json
```

### SQL Database Metrics

| Metric Name | API Metric | Aggregation | Notes |
|---|---|---|---|
| DTU Consumption % | `dtu_consumption_percent` | Maximum / Average | DTU-based SKUs only |
| CPU Percentage | `cpu_percent` | Maximum / Average | vCore-based SKUs |
| Storage Percentage | `storage_percent` | Maximum | Data space used |
| Session Count | `sessions_count` | Maximum | Active sessions |
| Workers Percentage | `workers_percent` | Maximum | Worker thread usage |
| Deadlocks | `deadlock` | Total | Deadlock count |

```bash
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Sql/servers/{serverName}/databases/{dbName}" \
  --metric "dtu_consumption_percent" "cpu_percent" "storage_percent" \
  --start-time "2026-02-06T00:00:00Z" \
  --end-time "2026-02-13T00:00:00Z" \
  --interval PT1H \
  --aggregation Maximum \
  --output json
```

---

## VMSS Metrics

### Per-Instance vs Aggregate

VMSS metrics can be collected at two levels:

| Level | Use Case | How |
|---|---|---|
| **Aggregate** | Overall VMSS health and rightsizing | Query the VMSS resource directly in Metrics API |
| **Per-Instance** | Individual instance analysis | Query each instance resource, or use KQL with Computer name matching |

For rightsizing recommendations, use **aggregate** metrics (the VMSS as a whole). For identifying hot/cold instances, use per-instance.

---

## Handling Missing Metrics

When metric data is unavailable for a resource:

| Scenario | Action | Data Quality |
|---|---|---|
| No `Perf` data, no `InsightsMetrics` | Fall back to Metrics API platform metrics | Minimal |
| No Metrics API data either | Check if VM is powered off / deallocated | None |
| Partial data (only CPU, no memory) | Proceed with available metrics, note gaps | Partial |
| Data exists but lookback is < 3 days | Warn that sample size is too small for reliable recommendations | Partial |
| VM was recently created (< 7 days) | Skip this VM, note "Insufficient data" | None |

**Decision rule:** If `dataQuality` is `None`, do NOT generate rightsizing recommendations. Only generate cleanup recommendations (deallocated, stopped) based on power state.

---

## Multi-Workspace Considerations

In large environments, VMs may send logs to different Log Analytics workspaces:

1. **Identify all workspaces** used across the target subscriptions:
   ```bash
   az monitor log-analytics workspace list --subscription <subscription-id> \
     --query "[].{name:name, id:customerId, resourceGroup:resourceGroup}" -o json
   ```

2. **Query each workspace separately** — KQL queries are scoped to a single workspace
3. **Cross-workspace queries** use the `workspace()` function but have performance implications:

```kql
union
    workspace("workspace-1").Perf,
    workspace("workspace-2").Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize cpuP99 = percentile(CounterValue, 99) by Computer
```

> **Best practice:** Query workspaces individually and merge results in the subagent code, rather than using cross-workspace queries which can time out.

---

## VM Extension Detection

List all extensions installed on a VM to infer workload type:

```bash
az vm extension list --resource-group <rg> --vm-name <vm> \
  --subscription <subscription-id> -o json
```

**Key extensions for workload inference:**

| Extension Name | Indicates |
|---|---|
| `SqlIaaSAgent` | SQL Server (confirmed) |
| `MicrosoftMonitoringAgent` | Legacy Log Analytics Agent |
| `AzureMonitorLinuxAgent` / `AzureMonitorWindowsAgent` | Azure Monitor Agent (AMA) — VM Insights available |
| `DependencyAgentWindows` / `DependencyAgentLinux` | Service Map data available |
| `CustomScriptExtension` | Custom workload |
| `IaaSDiagnostics` | Azure Diagnostics extension |

---

## NIC Accelerated Networking Check

Verify accelerated networking status for a VM's NICs:

```bash
# From VM directly (first NIC)
az vm show --ids <vm-resource-id> --query \
  "networkProfile.networkInterfaces[0].id" -o tsv

# Then check the NIC
az network nic show --ids <nic-resource-id> \
  --query "enableAcceleratedNetworking" -o json
```

Or query via ARG for bulk detection:
```kql
Resources
| where type =~ 'microsoft.network/networkinterfaces'
| where properties.enableAcceleratedNetworking == true
| project id, name, vmId = tostring(properties.virtualMachine.id)
```

> **FitScore impact:** If accelerated networking is enabled on the current
> VM's NIC and the target SKU does not support it
> (`AcceleratedNetworkingEnabled` capability), FitScore = 1 (hard constraint).

---

## Metric Collection Checklist

Before starting a scan, verify:

- [ ] Identify all target subscriptions
- [ ] Identify all Log Analytics workspaces receiving VM data
- [ ] Check AMA / VM Insights deployment status per VM
- [ ] Set lookback period (default 7d, respect tag overrides)
- [ ] Set time grain (PT1H)
- [ ] Set aggregation (P99 via KQL percentile)
- [ ] Handle pagination for Metrics API calls
- [ ] Classify data quality per resource
- [ ] Log any metrics collection errors without failing the entire scan
