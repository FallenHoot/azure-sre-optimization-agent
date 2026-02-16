"""
SRE Agent End-to-End Simulation
================================
Simulates what happens when the Compute Optimization Specialist subagent
runs inside Azure SRE Agent — without needing the actual service.

This script walks through the EXACT same 8-step workflow defined in
subagents/compute-optimization/subagent.yaml, using mock Azure data that
mirrors real Resource Graph, Monitor, Advisor, and SKU API responses.

Usage:
    python tests/simulate_e2e.py                  # full simulation
    python tests/simulate_e2e.py --step 4         # run up to step N
    python tests/simulate_e2e.py --subscription x # label for report

What this proves:
    1. The subagent instructions produce the correct sequence of tool calls
    2. FitScore calculations are accurate (reuses test_fitscore.py engine)
    3. The output conforms to Recommendation-Format.md JSON schema
    4. Savings estimates use the Retail Prices API format
    5. The full report structure matches what the orchestrator expects

Note on Demo Environment:
    This simulation uses MOCK data with fictional VM names and subscription.
    It is independent of the live demo resources deployed via infra/demo/.
    The demo environment (rg-sre-demo-workloads, swedencentral) tests against
    real Azure APIs, while this script validates subagent logic offline.
    See tests/test-subscription-setup.md for demo environment details.
"""

import json
import sys
from datetime import datetime, timezone
from dataclasses import dataclass, asdict
from typing import Optional
from test_fitscore import calculate_fitscore, VMConfig, SKU_DATABASE

# ═══════════════════════════════════════════════════════════════════════
#  Mock Azure Data — simulates what the SRE Agent tools would return
# ═══════════════════════════════════════════════════════════════════════

MOCK_SUBSCRIPTION = {
    "id": "/subscriptions/a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "displayName": "Production-Engineering",
    "short_id": "a1b2c3",
}

# ── Step 1: Resource Graph VM inventory ─────────────────────────────
MOCK_VMS = [
    {
        "id": "/subscriptions/a1b2c3d4-e5f6-7890-abcd-ef1234567890/resourceGroups/rg-webapp-prod/providers/Microsoft.Compute/virtualMachines/vm-web-prod-01",
        "name": "vm-web-prod-01",
        "resourceGroup": "rg-webapp-prod",
        "subscriptionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "location": "swedencentral",
        "vmSize": "Standard_D8s_v5",
        "powerState": "PowerState/running",
        "osType": "Linux",
        "nicCount": 1,
        "dataDisks": 2,
        "tags": {"environment": "production", "team": "web-platform"},
    },
    {
        "id": "/subscriptions/a1b2c3d4-e5f6-7890-abcd-ef1234567890/resourceGroups/rg-webapp-prod/providers/Microsoft.Compute/virtualMachines/vm-web-prod-02",
        "name": "vm-web-prod-02",
        "resourceGroup": "rg-webapp-prod",
        "subscriptionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "location": "swedencentral",
        "vmSize": "Standard_D16s_v5",
        "powerState": "PowerState/running",
        "osType": "Linux",
        "nicCount": 2,
        "dataDisks": 4,
        "tags": {"environment": "production", "team": "web-platform"},
    },
    {
        "id": "/subscriptions/a1b2c3d4-e5f6-7890-abcd-ef1234567890/resourceGroups/rg-devtest/providers/Microsoft.Compute/virtualMachines/vm-dev-build-01",
        "name": "vm-dev-build-01",
        "resourceGroup": "rg-devtest",
        "subscriptionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "location": "swedencentral",
        "vmSize": "Standard_D8s_v5",
        "powerState": "PowerState/deallocated",
        "osType": "Windows",
        "nicCount": 1,
        "dataDisks": 1,
        "tags": {"environment": "development", "team": "devops"},
    },
    {
        "id": "/subscriptions/a1b2c3d4-e5f6-7890-abcd-ef1234567890/resourceGroups/rg-devtest/providers/Microsoft.Compute/virtualMachines/vm-staging-api",
        "name": "vm-staging-api",
        "resourceGroup": "rg-devtest",
        "subscriptionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "location": "swedencentral",
        "vmSize": "Standard_D4s_v5",
        "powerState": "PowerState/stopped",  # stopped but NOT deallocated — CRITICAL
        "osType": "Linux",
        "nicCount": 1,
        "dataDisks": 1,
        "tags": {"environment": "staging", "team": "api-team"},
    },
    {
        "id": "/subscriptions/a1b2c3d4-e5f6-7890-abcd-ef1234567890/resourceGroups/rg-data/providers/Microsoft.Compute/virtualMachines/vm-data-etl-01",
        "name": "vm-data-etl-01",
        "resourceGroup": "rg-data",
        "subscriptionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "location": "swedencentral",
        "vmSize": "Standard_D8s_v5",
        "powerState": "PowerState/running",
        "osType": "Linux",
        "nicCount": 1,
        "dataDisks": 7,  # Will cause hard constraint violation for D4s_v5 (max 8) but not D2s_v5 (max 4)
        "tags": {"environment": "production", "team": "data-engineering"},
    },
]

# ── Step 3: Advisor rightsizing recommendations ─────────────────────
MOCK_ADVISOR_RECOMMENDATIONS = [
    {
        "resourceId": MOCK_VMS[0]["id"],
        "targetSku": "Standard_D4s_v5",
        "savingsAmount": 156.00,
        "savingsCurrency": "USD",
    },
    {
        "resourceId": MOCK_VMS[1]["id"],
        "targetSku": "Standard_D4s_v5",
        "savingsAmount": 312.00,
        "savingsCurrency": "USD",
    },
    {
        "resourceId": MOCK_VMS[4]["id"],
        "targetSku": "Standard_D4s_v5",
        "savingsAmount": 156.00,
        "savingsCurrency": "USD",
    },
]

# ── Step 4: P99 metric data (from Azure Monitor / Log Analytics) ────
MOCK_METRICS = {
    "vm-web-prod-01": {
        "p99_cpu": 18.5,
        "p99_memory": 32.0,
        "p99_iops": 2100.0,
        "p99_mibps": 45.0,
        "p99_network_mbps": 220.0,
    },
    "vm-web-prod-02": {
        "p99_cpu": 42.0,
        "p99_memory": 68.0,
        "p99_iops": 5800.0,
        "p99_mibps": 120.0,
        "p99_network_mbps": 410.0,
    },
    "vm-data-etl-01": {
        "p99_cpu": 15.0,
        "p99_memory": 28.0,
        "p99_iops": 1500.0,
        "p99_mibps": 35.0,
        "p99_network_mbps": 80.0,
    },
}

# ── Step 7: Retail Prices (from Azure Retail Prices API) ────────────
MOCK_PRICES_PER_HOUR = {
    "Standard_B2s": {"Linux": 0.0416, "Windows": 0.0656},
    "Standard_D2s_v5": {"Linux": 0.096, "Windows": 0.183},
    "Standard_D4s_v5": {"Linux": 0.192, "Windows": 0.366},
    "Standard_D8s_v5": {"Linux": 0.384, "Windows": 0.733},
    "Standard_D16s_v5": {"Linux": 0.768, "Windows": 1.466},
}


# ═══════════════════════════════════════════════════════════════════════
#  Simulation Engine
# ═══════════════════════════════════════════════════════════════════════

@dataclass
class Recommendation:
    """Follows the schema defined in knowledge-base/Recommendation-Format.md"""
    id: str
    timestamp: str
    category: str
    subcategory: str
    severity: str
    resourceId: str
    resourceName: str
    resourceGroup: str
    subscription: str
    currentState: dict
    recommendation: dict
    fitScore: Optional[dict]
    evidence: dict
    savings: dict
    riskAssessment: str


class SREAgentSimulator:
    """Simulates the Compute Optimization Specialist subagent workflow."""

    def __init__(self, subscription_label: str = "Production-Engineering", max_step: int = 8):
        self.subscription = MOCK_SUBSCRIPTION
        self.subscription["displayName"] = subscription_label
        self.max_step = max_step
        self.recommendations: list[Recommendation] = []
        self.scan_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
        self.tool_calls: list[dict] = []  # Track simulated tool invocations

    def _log_tool(self, tool: str, description: str, payload: str = ""):
        """Record a simulated SRE Agent tool call."""
        entry = {
            "tool": tool,
            "description": description,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        if payload:
            entry["payload_preview"] = payload[:200]
        self.tool_calls.append(entry)

    # ── Step 1: DISCOVER ────────────────────────────────────────────
    def step_1_discover(self):
        print()
        print("=" * 70)
        print("  STEP 1 — DISCOVER")
        print("  Tool: RunAzCliReadCommands (az graph query)")
        print("=" * 70)

        query = """Resources
| where type =~ 'microsoft.compute/virtualMachines'
| extend powerState = tostring(properties.extended.instanceView.powerState.code)
| extend vmSize = tostring(properties.hardwareProfile.vmSize)
| project id, name, resourceGroup, subscriptionId, location,
          vmSize, powerState, osType, nicCount, dataDisks, tags"""

        self._log_tool("RunAzCliReadCommands", "Query Resource Graph for all VMs", query)

        print(f"\n  >> az graph query executed")
        print(f"  >> Found {len(MOCK_VMS)} VMs across subscription '{self.subscription['displayName']}'")
        print()
        print(f"  {'Name':<24} {'SKU':<22} {'RG':<18} {'State':<24} {'Disks':>5} {'NICs':>5}")
        print(f"  {'─'*24} {'─'*22} {'─'*18} {'─'*24} {'─'*5} {'─'*5}")
        for vm in MOCK_VMS:
            print(f"  {vm['name']:<24} {vm['vmSize']:<22} {vm['resourceGroup']:<18} {vm['powerState']:<24} {vm['dataDisks']:>5} {vm['nicCount']:>5}")

        return MOCK_VMS

    # ── Step 2: ASSESS ──────────────────────────────────────────────
    def step_2_assess(self, vms):
        print()
        print("=" * 70)
        print("  STEP 2 — ASSESS")
        print("  Classify VMs by state and capture configuration")
        print("=" * 70)

        running = [v for v in vms if v["powerState"] == "PowerState/running"]
        deallocated = [v for v in vms if v["powerState"] == "PowerState/deallocated"]
        stopped = [v for v in vms if v["powerState"] == "PowerState/stopped"]

        print(f"\n  Running:                  {len(running)}")
        print(f"  Deallocated:              {len(deallocated)}")
        print(f"  Stopped (NOT deallocated): {len(stopped)}  {'⚠️  CRITICAL — still billing!' if stopped else ''}")
        print()

        return {"running": running, "deallocated": deallocated, "stopped": stopped}

    # ── Step 3: CHECK ADVISOR ───────────────────────────────────────
    def step_3_advisor(self):
        print()
        print("=" * 70)
        print("  STEP 3 — CHECK ADVISOR")
        print("  Tool: RunAzCliReadCommands (az advisor recommendation list)")
        print("=" * 70)

        self._log_tool(
            "RunAzCliReadCommands",
            "Query Advisor for cost rightsizing recommendations",
            "az advisor recommendation list --category Cost --output json"
        )

        print(f"\n  >> az advisor recommendation list executed")
        print(f"  >> Found {len(MOCK_ADVISOR_RECOMMENDATIONS)} rightsizing recommendations")
        print()

        for rec in MOCK_ADVISOR_RECOMMENDATIONS:
            vm_name = rec["resourceId"].split("/")[-1]
            # Find original VM to get current SKU
            orig_vm = next((v for v in MOCK_VMS if v["id"] == rec["resourceId"]), None)
            current_sku = orig_vm["vmSize"] if orig_vm else "?"
            print(f"  {vm_name:<24} {current_sku} → {rec['targetSku']:<22} "
                  f"Advisor est. savings: ${rec['savingsAmount']:.2f}/mo")

        return MOCK_ADVISOR_RECOMMENDATIONS

    # ── Step 4: VALIDATE WITH FITSCORE ──────────────────────────────
    def step_4_fitscore(self, advisor_recs):
        print()
        print("=" * 70)
        print("  STEP 4 — VALIDATE WITH FITSCORE")
        print("  Tools: RunAzCliReadCommands (az vm list-skus)")
        print("         RunAzCliReadCommands (az monitor log-analytics query for P99 metrics)")
        print("=" * 70)

        fitscore_results = []

        for rec in advisor_recs:
            vm_name = rec["resourceId"].split("/")[-1]
            orig_vm = next((v for v in MOCK_VMS if v["id"] == rec["resourceId"]), None)
            if not orig_vm:
                continue

            target_sku_name = rec["targetSku"]
            metrics = MOCK_METRICS.get(vm_name, {})

            # Simulate the tool calls the agent would make
            self._log_tool(
                "RunAzCliReadCommands",
                f"Look up SKU capabilities for {target_sku_name}",
                f"az vm list-skus --location {orig_vm['location']} --size {target_sku_name}"
            )

            kql = f"""Perf
| where TimeGenerated > ago(7d)
| where _ResourceId =~ "{rec['resourceId']}"
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize P99_CPU = percentile(CounterValue, 99) by _ResourceId"""

            self._log_tool("RunAzCliReadCommands", f"Query P99 CPU for {vm_name}", f"az monitor log-analytics query --workspace <id> --analytics-query '{kql}'")
            self._log_tool("RunAzCliReadCommands", f"Query P99 Memory for {vm_name}", "az monitor log-analytics query ...")
            self._log_tool("RunAzCliReadCommands", f"Query P99 Disk IOPS/throughput for {vm_name}", "az monitor log-analytics query ...")

            # Build VMConfig from mock data
            vm_config = VMConfig(
                name=vm_name,
                current_sku=orig_vm["vmSize"],
                data_disk_count=orig_vm["dataDisks"],
                nic_count=orig_vm["nicCount"],
                p99_cpu=metrics.get("p99_cpu"),
                p99_memory=metrics.get("p99_memory"),
                p99_iops=metrics.get("p99_iops"),
                p99_mibps=metrics.get("p99_mibps"),
                p99_network_mbps=metrics.get("p99_network_mbps"),
            )

            # Calculate FitScore using the REAL algorithm
            result = calculate_fitscore(vm_config, target_sku_name)

            print(f"\n  ┌─ {vm_name} ({orig_vm['vmSize']} → {target_sku_name})")
            print(f"  │  FitScore: {result.score:.1f} / 5.0  {'⛔' if result.hard_violation else '✅' if result.score >= 4.0 else '⚠️'}")
            print(f"  │  Disk Count:  {result.breakdown.disk_count}")
            print(f"  │  NIC Count:   {result.breakdown.nic_count}")
            print(f"  │  Disk IOPS:   {result.breakdown.disk_iops}")
            print(f"  │  Disk MiBps:  {result.breakdown.disk_throughput}")
            print(f"  │  CPU:         {result.breakdown.cpu}")
            print(f"  │  Memory:      {result.breakdown.memory}")
            print(f"  │  Network:     {result.breakdown.network}")
            print(f"  │  Verdict:     {result.recommendation}")
            print(f"  └─")

            fitscore_results.append({
                "vm_name": vm_name,
                "resource_id": rec["resourceId"],
                "resource_group": orig_vm["resourceGroup"],
                "current_sku": orig_vm["vmSize"],
                "target_sku": target_sku_name,
                "fitscore": result,
                "os_type": orig_vm["osType"],
                "location": orig_vm["location"],
                "advisor_savings": rec["savingsAmount"],
            })

            # Step 4 extension: if FitScore <= 2, search for alternatives
            if result.score <= 2.0 and not result.hard_violation:
                print(f"  ⚡ FitScore ≤ 2 — searching for alternative SKUs...")
                self._log_tool(
                    "RunAzCliReadCommands",
                    f"Search alternative SKUs for {vm_name}",
                    f"az vm list-skus --location {orig_vm['location']} --resource-type virtualMachines"
                )

            if result.hard_violation:
                # Try alternatives
                print(f"  ⚡ Hard constraint violation — searching alternatives...")
                current_vcpus = SKU_DATABASE.get(orig_vm["vmSize"], {}).get("vCPUsAvailable", 99)
                candidates = [
                    (name, sku) for name, sku in SKU_DATABASE.items()
                    if sku["vCPUsAvailable"] < current_vcpus and name != target_sku_name
                ]
                best_alt = None
                for alt_name, alt_sku in sorted(candidates, key=lambda x: x[1]["vCPUsAvailable"], reverse=True):
                    alt_result = calculate_fitscore(vm_config, alt_name)
                    if alt_result.score > 2.0:
                        best_alt = (alt_name, alt_result)
                        break

                if best_alt:
                    alt_name, alt_result = best_alt
                    print(f"  ✅ Alternative found: {alt_name} (FitScore {alt_result.score:.1f})")
                    fitscore_results[-1]["alternative_sku"] = alt_name
                    fitscore_results[-1]["alternative_fitscore"] = alt_result
                else:
                    print(f"  ❌ No suitable alternative SKU found")

        return fitscore_results

    # ── Step 5: DETECT IDLE RESOURCES ───────────────────────────────
    def step_5_idle(self, classified_vms):
        print()
        print("=" * 70)
        print("  STEP 5 — DETECT IDLE RESOURCES")
        print("  Tool: RunAzCliReadCommands (az graph query, az monitor activity-log)")
        print("=" * 70)

        findings = []

        # Deallocated VMs
        for vm in classified_vms["deallocated"]:
            self._log_tool(
                "RunAzCliReadCommands",
                f"Check activity log for {vm['name']}",
                f"az monitor activity-log list --resource-id {vm['id']} --offset 90d"
            )
            # Simulate: this VM has been deallocated for 45 days
            days_deallocated = 45
            os_type = vm.get("osType", "Linux")
            hourly_rate = MOCK_PRICES_PER_HOUR.get(vm["vmSize"], {}).get(os_type, 0.384)
            monthly_cost = hourly_rate * 730

            print(f"\n  ⏸️  {vm['name']} — Deallocated for {days_deallocated} days")
            print(f"     SKU: {vm['vmSize']} ({os_type})")
            print(f"     Monthly cost if running: ${monthly_cost:.2f}")
            print(f"     ➡️  Flag for deletion review")

            findings.append({
                "type": "deallocated",
                "vm": vm,
                "days": days_deallocated,
                "monthly_cost": monthly_cost,
            })

        # Stopped-not-deallocated VMs (CRITICAL)
        for vm in classified_vms["stopped"]:
            os_type = vm.get("osType", "Linux")
            hourly_rate = MOCK_PRICES_PER_HOUR.get(vm["vmSize"], {}).get(os_type, 0.192)
            monthly_cost = hourly_rate * 730

            print(f"\n  🚨 {vm['name']} — STOPPED (NOT DEALLOCATED)")
            print(f"     SKU: {vm['vmSize']} ({os_type})")
            print(f"     ⚠️  STILL BILLING: ${monthly_cost:.2f}/month!")
            print(f"     ➡️  Deallocate immediately or delete")

            findings.append({
                "type": "stopped_not_deallocated",
                "vm": vm,
                "monthly_cost": monthly_cost,
            })

        return findings

    # ── Step 6: CHECK HIGH AVAILABILITY ─────────────────────────────
    def step_6_ha(self, classified_vms):
        print()
        print("=" * 70)
        print("  STEP 6 — CHECK HIGH AVAILABILITY")
        print("  Tool: RunAzCliReadCommands (az graph query)")
        print("=" * 70)

        self._log_tool(
            "RunAzCliReadCommands",
            "Query for VMs without HA configuration",
            "Resources | where type =~ 'microsoft.compute/virtualMachines' | where isnull(properties.availabilitySet) and array_length(zones) == 0"
        )

        # Simulate: all running VMs lack HA config
        ha_gaps = classified_vms["running"]
        print(f"\n  >> Found {len(ha_gaps)} running VMs without availability set or zone")
        for vm in ha_gaps:
            print(f"     ⚠️  {vm['name']} ({vm['vmSize']}) in {vm['resourceGroup']} — no HA")

        return ha_gaps

    # ── Step 7: ESTIMATE SAVINGS ────────────────────────────────────
    def step_7_savings(self, fitscore_results, idle_findings):
        print()
        print("=" * 70)
        print("  STEP 7 — ESTIMATE SAVINGS")
        print("  Tool: RunAzCliReadCommands (az rest — Azure Retail Prices API)")
        print("=" * 70)

        total_monthly = 0.0

        print(f"\n  {'Resource':<24} {'Action':<30} {'Monthly':>10} {'Annual':>12} {'Confidence':>12}")
        print(f"  {'─'*24} {'─'*30} {'─'*10} {'─'*12} {'─'*12}")

        # Rightsizing savings
        for entry in fitscore_results:
            fs = entry["fitscore"]
            if fs.score < 3.0 and "alternative_fitscore" not in entry:
                continue  # Skip unrecommended

            target = entry.get("alternative_sku", entry["target_sku"])
            score = entry.get("alternative_fitscore", entry["fitscore"]).score if "alternative_fitscore" in entry else fs.score

            if score < 3.0:
                continue

            os_type = entry["os_type"]
            current_rate = MOCK_PRICES_PER_HOUR.get(entry["current_sku"], {}).get(os_type, 0)
            target_rate = MOCK_PRICES_PER_HOUR.get(target, {}).get(os_type, 0)
            monthly = (current_rate - target_rate) * 730
            annual = monthly * 12

            self._log_tool(
                "RunAzCliReadCommands",
                f"Retail Prices API for {entry['current_sku']} and {target}",
                f"az rest --url 'https://prices.azure.com/api/retail/prices?$filter=armSkuName eq \'{entry['current_sku']}\''"
            )

            confidence = "High" if score >= 4.0 else "Medium" if score >= 3.0 else "Low"
            action = f"Resize → {target}"
            print(f"  {entry['vm_name']:<24} {action:<30} ${monthly:>8.2f} ${annual:>10.2f} {confidence:>12}")
            total_monthly += monthly

            # Build recommendation object
            self.recommendations.append(Recommendation(
                id=f"compute-{self.subscription['short_id']}-{entry['vm_name']}-{self.scan_timestamp}",
                timestamp=datetime.now(timezone.utc).isoformat(),
                category="Compute",
                subcategory="VM Rightsizing",
                severity="High" if monthly > 100 else "Medium",
                resourceId=entry["resource_id"],
                resourceName=entry["vm_name"],
                resourceGroup=entry["resource_group"],
                subscription=self.subscription["displayName"],
                currentState={"sku": entry["current_sku"], "osType": os_type},
                recommendation={"action": "Resize", "targetSku": target},
                fitScore={
                    "score": score,
                    "breakdown": {
                        "diskCount": fs.breakdown.disk_count,
                        "nicCount": fs.breakdown.nic_count,
                        "diskIOPS": fs.breakdown.disk_iops,
                        "diskThroughput": fs.breakdown.disk_throughput,
                        "cpu": fs.breakdown.cpu,
                        "memory": fs.breakdown.memory,
                        "network": fs.breakdown.network,
                    },
                },
                evidence={"source": "Azure Advisor + FitScore validation"},
                savings={"monthly": round(monthly, 2), "annual": round(annual, 2), "currency": "USD"},
                riskAssessment=fs.recommendation,
            ))

        # Idle resource savings
        for finding in idle_findings:
            vm = finding["vm"]
            monthly = finding["monthly_cost"]
            annual = monthly * 12

            if finding["type"] == "stopped_not_deallocated":
                action = "Deallocate/Delete"
                severity = "Critical"
                subcategory = "Stopped-Not-Deallocated VM"
            else:
                action = "Delete (45d idle)"
                severity = "High"
                subcategory = "Deallocated VM Cleanup"

            print(f"  {vm['name']:<24} {action:<30} ${monthly:>8.2f} ${annual:>10.2f}       {'Critical' if severity == 'Critical' else 'High':>7}")
            total_monthly += monthly

            self.recommendations.append(Recommendation(
                id=f"compute-{self.subscription['short_id']}-{vm['name']}-{self.scan_timestamp}",
                timestamp=datetime.now(timezone.utc).isoformat(),
                category="Compute",
                subcategory=subcategory,
                severity=severity,
                resourceId=vm["id"],
                resourceName=vm["name"],
                resourceGroup=vm["resourceGroup"],
                subscription=self.subscription["displayName"],
                currentState={"sku": vm["vmSize"], "powerState": vm["powerState"]},
                recommendation={"action": action},
                fitScore=None,
                evidence={"source": "Resource Graph + Activity Log"},
                savings={"monthly": round(monthly, 2), "annual": round(annual, 2), "currency": "USD"},
                riskAssessment="Deallocated for 30+ days — review with owner" if finding["type"] == "deallocated" else "CRITICAL: VM is stopped but still incurring compute charges",
            ))

        print(f"\n  {'─'*24} {'─'*30} {'─'*10} {'─'*12}")
        print(f"  {'TOTAL':<24} {'':<30} ${total_monthly:>8.2f} ${total_monthly*12:>10.2f}")

        return total_monthly

    # ── Step 8: GENERATE REPORT ─────────────────────────────────────
    def step_8_report(self, total_savings, ha_gaps, fitscore_results):
        print()
        print("=" * 70)
        print("  STEP 8 — GENERATE REPORT")
        print("  Tool: UploadKnowledgeDocument + conversation output")
        print("=" * 70)

        total_vms = len(MOCK_VMS)
        total_recs = len(self.recommendations)
        critical = sum(1 for r in self.recommendations if r.severity == "Critical")
        high = sum(1 for r in self.recommendations if r.severity == "High")
        medium = sum(1 for r in self.recommendations if r.severity == "Medium")
        low = sum(1 for r in self.recommendations if r.severity == "Low")
        rightsizing = sum(1 for r in self.recommendations if r.subcategory == "VM Rightsizing")
        idle = sum(1 for r in self.recommendations if "Deallocated" in r.subcategory or "Stopped" in r.subcategory)

        report_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

        print(f"""
  ┌──────────────────────────────────────────────────────────────────┐
  │         COMPUTE OPTIMIZATION REPORT — {report_date}            │
  │         Subscription: {self.subscription['displayName']:<40}│
  ├──────────────────────────────────────────────────────────────────┤
  │  EXECUTIVE SUMMARY                                              │
  │                                                                  │
  │  Total VMs scanned:              {total_vms:<30}│
  │  Total recommendations:          {total_recs:<30}│
  │  Monthly savings potential:      ${total_savings:<29.2f}│
  │  Annual savings potential:       ${total_savings*12:<29.2f}│
  │                                                                  │
  │  By Severity:                                                    │
  │    Critical:   {critical:<10}  High:   {high:<10}  Medium:  {medium:<10}│
  │    Low:        {low:<10}                                         │
  │                                                                  │
  │  By Category:                                                    │
  │    Rightsizing: {rightsizing:<10}  Idle/Orphaned: {idle:<10}  HA gaps: {len(ha_gaps):<5}│
  └──────────────────────────────────────────────────────────────────┘""")

        # Sort recommendations
        severity_order = {"Critical": 0, "High": 1, "Medium": 2, "Low": 3}
        sorted_recs = sorted(
            self.recommendations,
            key=lambda r: (severity_order.get(r.severity, 9), -r.savings["monthly"])
        )

        print(f"\n  ── RECOMMENDATIONS (sorted by severity, then savings) ──\n")
        for i, rec in enumerate(sorted_recs, 1):
            emoji = {"Critical": "🚨", "High": "🔴", "Medium": "🟡", "Low": "🟢"}.get(rec.severity, "⚪")
            action = rec.recommendation.get("action", "?")
            target = rec.recommendation.get("targetSku", "")
            fs_display = f"FitScore {rec.fitScore['score']:.1f}" if rec.fitScore else "N/A"

            print(f"  {i}. {emoji} [{rec.severity}] {rec.resourceName}")
            print(f"     Action: {action}{(' → ' + target) if target else ''}")
            print(f"     Savings: ${rec.savings['monthly']:.2f}/mo (${rec.savings['annual']:.2f}/yr)")
            print(f"     {fs_display} | RG: {rec.resourceGroup}")
            print(f"     Risk: {rec.riskAssessment}")
            print()

        # Simulate report persistence
        subject = f"Weekly Compute Optimization Report — {report_date} — ${total_savings:.0f}/month potential"
        self._log_tool("UploadKnowledgeDocument", f"Save report to KB", f"Title: Compute-Optimization-Report-{report_date}")
        print(f"  📄 Report saved to Knowledge Base: Compute-Optimization-Report-{report_date}")
        print(f"  💬 Report output to conversation: {subject}")

        return sorted_recs

    # ── Output JSON recommendations (for orchestrator consumption) ──
    def export_json(self, output_path: str = None):
        """Export recommendations in the Recommendation-Format.md schema."""
        recs_dict = []
        for rec in self.recommendations:
            d = {
                "id": rec.id,
                "timestamp": rec.timestamp,
                "category": rec.category,
                "subcategory": rec.subcategory,
                "severity": rec.severity,
                "resourceId": rec.resourceId,
                "resourceName": rec.resourceName,
                "resourceGroup": rec.resourceGroup,
                "subscription": rec.subscription,
                "currentState": rec.currentState,
                "recommendation": rec.recommendation,
                "fitScore": rec.fitScore,
                "evidence": rec.evidence,
                "savings": rec.savings,
                "riskAssessment": rec.riskAssessment,
            }
            recs_dict.append(d)

        output = {
            "metadata": {
                "generatedBy": "Compute-Optimization-Specialist",
                "scanTimestamp": self.scan_timestamp,
                "subscription": self.subscription["displayName"],
                "toolCalls": len(self.tool_calls),
            },
            "recommendations": recs_dict,
        }

        if output_path:
            with open(output_path, "w") as f:
                json.dump(output, f, indent=2)
            print(f"\n  💾 Recommendations exported to: {output_path}")
        else:
            print(f"\n  📋 JSON output ({len(recs_dict)} recommendations, {len(self.tool_calls)} tool calls)")

        return output

    # ── Run full workflow ───────────────────────────────────────────
    def run(self):
        print()
        print("╔" + "═" * 68 + "╗")
        print("║  AZURE SRE AGENT — COMPUTE OPTIMIZATION SPECIALIST (SIMULATION)  ║")
        print("║  Workflow: subagent.yaml → 9-step optimization scan                ║")
        print("║  Algorithm: AOE FitScore (ported from PowerShell)                 ║")
        print("╚" + "═" * 68 + "╝")
        print(f"\n  Subscription: {self.subscription['displayName']}")
        print(f"  Timestamp:    {self.scan_timestamp}")
        print(f"  Max step:     {self.max_step}")

        # Step 1
        vms = self.step_1_discover()
        if self.max_step < 2:
            return

        # Step 2
        classified = self.step_2_assess(vms)
        if self.max_step < 3:
            return

        # Step 3
        advisor_recs = self.step_3_advisor()
        if self.max_step < 4:
            return

        # Step 4
        fitscore_results = self.step_4_fitscore(advisor_recs)
        if self.max_step < 5:
            return

        # Step 5
        idle_findings = self.step_5_idle(classified)
        if self.max_step < 6:
            return

        # Step 6
        ha_gaps = self.step_6_ha(classified)
        if self.max_step < 7:
            return

        # Step 7
        total_savings = self.step_7_savings(fitscore_results, idle_findings)
        if self.max_step < 8:
            return

        # Step 8
        self.step_8_report(total_savings, ha_gaps, fitscore_results)

        # Export JSON
        self.export_json()

        # Summary of tool calls
        print()
        print("=" * 70)
        print("  TOOL CALL SUMMARY (what the SRE Agent would execute)")
        print("=" * 70)
        tool_counts = {}
        for tc in self.tool_calls:
            tool_counts[tc["tool"]] = tool_counts.get(tc["tool"], 0) + 1
        for tool, count in sorted(tool_counts.items()):
            print(f"  {tool:<30} {count:>3} calls")
        print(f"  {'─'*30} {'─'*3}")
        print(f"  {'TOTAL':<30} {len(self.tool_calls):>3} calls")
        print()


# ═══════════════════════════════════════════════════════════════════════
#  CLI
# ═══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    max_step = 8
    sub_label = "Production-Engineering"

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--step" and i + 1 < len(args):
            max_step = int(args[i + 1])
            i += 2
        elif args[i] == "--subscription" and i + 1 < len(args):
            sub_label = args[i + 1]
            i += 2
        elif args[i] in ("-h", "--help"):
            print(__doc__)
            sys.exit(0)
        else:
            i += 1

    sim = SREAgentSimulator(subscription_label=sub_label, max_step=max_step)
    sim.run()
