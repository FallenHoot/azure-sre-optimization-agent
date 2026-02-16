# Test Scenario: Deallocated VM (30+ Days)

## Objective

Validate that the compute optimization subagent correctly identifies VMs that have been deallocated for 30+ days and recommends deletion with full cost savings (reserved IP, disk, etc.).

---

## Demo Resource

| Property | Value |
|---|---|
| **VM Name** | `vm-nozone-staging` (deallocated manually post-deploy) |
| **Resource Group** | `rg-sre-demo-workloads` |
| **Region** | swedencentral |
| **SKU** | Standard_D2s_v3 (2 vCPU / 8 GiB) |
| **OS Disk** | 128 GB StandardSSD_LRS |
| **Tags** | `environment=staging`, `workload=api-backend` |
| **Deployed By** | [`infra/demo/modules/demo-resources.bicep`](../../infra/demo/modules/demo-resources.bicep) — module `vm3` |

> **Note:** This VM deploys in a running state. You must **manually deallocate** it after deployment to test this scenario.

---

## Setup

1. Deploy the demo environment:

```powershell
cd infra/demo
.\deploy-demo.ps1
```

2. Deallocate the VM:

```powershell
az vm deallocate --resource-group rg-sre-demo-workloads --name vm-nozone-staging
```

3. Verify deallocated state:

```powershell
az vm get-instance-view `
  --resource-group rg-sre-demo-workloads `
  --name vm-nozone-staging `
  --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus" `
  --output tsv
```

Expected output: `VM deallocated`

---

## Waiting Period

The subagent checks the Azure Activity Log to determine how long the VM has been deallocated. You need to wait **30+ days** for the activity log to reflect prolonged deallocation.

### Accelerated Testing (Without Waiting 30 Days)

For PoC testing, you can validate the logic by:

1. **Query the Activity Log directly** to verify the subagent's query works:

```powershell
az monitor activity-log list `
  --resource-group rg-sre-demo-workloads `
  --offset 30d `
  --query "[?contains(resourceId, 'vm-nozone-staging') && operationName.value=='Microsoft.Compute/virtualMachines/start/action'].{Time:eventTimestamp, Status:status.value}" `
  --output table
```

2. **Modify the threshold temporarily** in the knowledge base to use a shorter window (e.g., 1 day) for testing purposes.

3. **Use a pre-existing deallocated VM** in a dev/test subscription that has been idle for 30+ days.

---

## Expected Results

| Check | Expected |
|---|---|
| VM power state | Deallocated |
| Days since last power-on | ≥ 30 |
| Subagent detection | Flagged as long-term deallocated |
| Recommendation | Delete VM and associated resources |
| FitScore | N/A (not a resize — binary delete recommendation) |
| Estimated savings | Full cost of retained resources |

### Retained Resource Costs (Still Billing While Deallocated)

| Resource | Estimated Monthly Cost |
|---|---|
| OS Disk (128 GiB StandardSSD) | ~$10 |
| NIC | $0 |
| **Total retained cost** | **~$10/month** |

> Note: Compute charges stop when deallocated, but disk charges continue. No public IP in demo.

---

## Expected Subagent Output

```markdown
## vm-nozone-staging (Standard_D2s_v3) — DEALLOCATED 30+ DAYS

- **Status:** Deallocated since YYYY-MM-DD (XX days ago)
- **Recommendation:** Delete VM and associated resources
- **Retained Monthly Cost:** ~$10/month
- **Risk:** Low (VM has not been used in 30+ days)

### Action Items
1. Confirm with resource owner that the VM is no longer needed
2. Snapshot the OS disk if data retention is required
3. Delete the VM and all associated resources

### Cleanup Commands
```powershell
# Snapshot OS disk (optional, for data retention)
az snapshot create `
  --resource-group rg-sre-demo-workloads `
  --name snap-nozone-staging-os `
  --source $(az vm show -g rg-sre-demo-workloads -n vm-nozone-staging --query "storageProfile.osDisk.managedDisk.id" -o tsv)

# Delete VM
az vm delete --resource-group rg-sre-demo-workloads --name vm-nozone-staging --yes
```
```

---

## Verification Steps

1. ✅ Confirm VM is in deallocated state
2. ✅ Confirm activity log shows no start events in 30+ days
3. ✅ Run the compute subagent against the demo subscription
4. ✅ Verify the subagent flags the VM as deallocated 30+ days
5. ✅ Verify the recommendation is "delete" (not "resize")
6. ✅ Verify the output lists all retained resources and their costs
7. ✅ Verify the output includes cleanup CLI commands

---

## Edge Cases

| Scenario | Expected Behavior |
|---|---|
| VM deallocated for 29 days | Not flagged (below threshold) |
| VM deallocated for 31 days | Flagged for deletion |
| VM deallocated, then started briefly, then deallocated again | 30-day clock resets from last deallocation |
| VM deallocated with multiple data disks | All disk costs included in savings estimate |

---

## Cleanup

Resources are managed by the demo environment. To clean up everything:

```powershell
az group delete --name rg-sre-demo-workloads --yes --no-wait
```
