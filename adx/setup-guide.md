# SRE Optimization Engine — ADX Setup Guide

> Step-by-step instructions to deploy the SREOptimization database on your existing FinOps Hub ADX cluster.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| FinOps Hub with ADX | [Deploy guide](https://learn.microsoft.com/cloud-computing/finops/toolkit/hubs/deploy) |
| ADX cluster access | Database Admin permissions on the FinOps Hub cluster |
| SRE Agent | Running `Microsoft.App/agents` with managed identity |
| Azure CLI | v2.60+ with `kusto` extension |
| KQL tools | Azure Data Explorer web UI or Kusto.Explorer |

## Step 1: Identify your FinOps Hub ADX cluster

```bash
# List ADX clusters in your FinOps Hub resource group
az kusto cluster list \
  --resource-group <finops-hub-rg> \
  --query "[].{name:name, uri:uri, state:state, sku:sku.name}" \
  --output table
```

Note the cluster **name** and **URI** (e.g., `https://<cluster>.swedencentral.kusto.windows.net`).

## Step 2: Create the SREOptimization database

```bash
# Create a new read-write database on the existing cluster
az kusto database create \
  --cluster-name <finops-hub-cluster> \
  --resource-group <finops-hub-rg> \
  --database-name SREOptimization \
  --read-write-database soft-delete-period=P365D hot-cache-period=P31D

# Verify it was created alongside Hub and Ingestion databases
az kusto database list \
  --cluster-name <finops-hub-cluster> \
  --resource-group <finops-hub-rg> \
  --query "[].name" \
  --output table
```

Expected output:
```
Name
-----------------
Hub
Ingestion
SREOptimization
```

## Step 3: Create tables and functions

1. Open [Azure Data Explorer web UI](https://dataexplorer.azure.com)
2. Connect to your cluster: `https://<cluster>.<region>.kusto.windows.net`
3. Select the **SREOptimization** database
4. Open [schema.kql](schema.kql) and run each section in order:
   - **Step 1**: Create all 5 tables (Scans, Recommendations, SavingsTracking, ResourceSnapshots, AgentMetrics)
   - **Step 2**: Create ingestion mappings (JSON format)
   - **Step 3**: Set retention policies
   - **Step 4**: Create helper functions

### Verify tables were created

```kusto
.show tables
| project TableName, Folder, DocString, RetentionPolicy
```

### Verify functions were created

```kusto
.show functions
| project Name, Parameters, Body
```

## Step 4: Configure RBAC for SRE Agent

The SRE Agent managed identity needs:
- **Database Viewer** on `Hub` and `Ingestion` (read FOCUS cost data)
- **Database Admin** on `SREOptimization` (write scan results)

```bash
# Get the SRE Agent managed identity principal ID
SRE_IDENTITY_PRINCIPAL=$(az identity show \
  --name <sre-agent-identity-name> \
  --resource-group <sre-agent-rg> \
  --query principalId --output tsv)

echo "SRE Agent principal ID: $SRE_IDENTITY_PRINCIPAL"
```

Run these KQL commands in the Azure Data Explorer web UI:

```kusto
// Grant Viewer on Hub database (for reading FOCUS Costs/Prices)
.add database ['Hub'] viewers ('aadapp=<sre-agent-managed-identity-client-id>;<tenant-id>') 'SRE Agent - read costs'

// Grant Viewer on Ingestion database (for reading raw cost tables)
.add database ['Ingestion'] viewers ('aadapp=<sre-agent-managed-identity-client-id>;<tenant-id>') 'SRE Agent - read raw data'

// Grant Admin on SREOptimization database (for writing scan results)
.add database ['SREOptimization'] admins ('aadapp=<sre-agent-managed-identity-client-id>;<tenant-id>') 'SRE Agent - write results'
```

### Verify RBAC

```kusto
.show database ['SREOptimization'] principals
```

## Step 5: Test cross-database queries

After RBAC is configured, verify that the SREOptimization database can read from Hub:

```kusto
// Test: read FOCUS cost data from Hub database
database('Hub').Costs
| take 5
| project ResourceId, ResourceName, EffectiveCost, ChargePeriodStart

// Test: read pricing data
database('Hub').Prices
| take 5

// Test: read from Ingestion
database('Ingestion').Regions
| take 5
```

If these return results, cross-database queries are working.

## Step 6: Load sample data (optional — for testing)

To test the dashboard before the SRE Agent writes real data, ingest sample records:

```kusto
// Sample scan record
.ingest inline into table Scans <|
d4a7b3c1-2e5f-4a8b-9c1d-3e5f7a9b1c3d,2026-02-16T10:00:00Z,compute,Compute-Optimization-Specialist,"[""529744b7-01d5-4f39-9d5b-3ccdea48ab04""]",3,5,283.0,3396.0,180,completed,,scheduled

// Sample recommendation record
.ingest inline into table Recommendations <|
a1b2c3d4-e5f6-7890-abcd-ef1234567890,d4a7b3c1-2e5f-4a8b-9c1d-3e5f7a9b1c3d,2026-02-16T10:00:00Z,compute,rightsizing,Medium,/subscriptions/529744b7-01d5-4f39-9d5b-3ccdea48ab04/resourceGroups/rg-sre-demo-workloads/providers/Microsoft.Compute/virtualMachines/vm-oversized-sredemo,vm-oversized-sredemo,microsoft.compute/virtualmachines,rg-sre-demo-workloads,529744b7-01d5-4f39-9d5b-3ccdea48ab04,SRE Demo Subscription,Compute,swedencentral,Standard_D8s_v3,Standard_D4s_v5,4.0,"{""disks"":""PASS"",""nics"":""PASS"",""premiumIO"":""PASS""}",283.0,3396.0,430.0,147.0,Safe,P99 CPU 12% P99 Mem 28%,Unknown,pending,,"{""project"":""sre-optimization-engine""}"
```

Then verify:

```kusto
Scans | take 10
Recommendations | take 10
ActiveRecommendations | count
SavingsSummary
```

## Step 7: Create the ADX dashboard

1. Go to [Azure Data Explorer Dashboards](https://dataexplorer.azure.com/dashboards)
2. Click **+ New Dashboard** → name: `SRE Optimization Engine`
3. Add your cluster as a data source
4. Create pages following [dashboard-pages.md](dashboard-pages.md)
5. Pin queries from [queries.kql](queries.kql) to each tile
6. Set auto-refresh interval: **1 hour** (or manual refresh after scans)
7. Share the dashboard URL with your team

### Dashboard parameters (global filters)

Add these as dashboard-level parameters:

| Parameter | Type | Source | Default |
|-----------|------|--------|---------|
| `TimeRange` | Time range | Preset | Last 30 days |
| `Domain` | Multi-select | `Recommendations \| distinct Domain` | All |
| `Severity` | Multi-select | Static: Critical, High, Medium, Low | All |
| `Subscription` | Multi-select | `Recommendations \| distinct SubAccountName` | All |

## Step 8: (Future) Connect SRE Agent Kusto Tool

Once the SRE Agent's **Kusto Tool** is configured, the agent can:

1. **Write** scan results directly to the `SREOptimization` database after each scan
2. **Read** FOCUS cost data from `Hub.Costs` to enrich recommendations with actual spend
3. **Query** historical trends to compare current findings with past scans

This integration will be configured via the SRE Agent's `schedule.yaml` and `subagent.yaml` files once the community confirms interest.

---

## Architecture cost impact

| Component | Cost impact |
|-----------|-------------|
| New `SREOptimization` database | **$0** — same cluster, shared compute |
| Data storage | **~$0.01/GB/mo** — hot cache on existing cluster |
| Expected data volume | ~1 MB per scan → <100 MB/year |
| ADX Dashboard | **$0** — free, included with ADX |
| Total additional cost | **≈ $0/mo** |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Access denied` on `database('Hub').Costs` | Check RBAC: SRE identity needs Viewer on Hub database |
| `Database not found: SREOptimization` | Verify database was created on the correct cluster |
| Empty `Costs()` function results | Ensure FinOps Hub data pipeline has run (check ADF) |
| Ingestion mapping errors | Ensure JSON field names match the mapping in schema.kql |
| `Kusto query timeout` | Add time filters to narrow query scope |
