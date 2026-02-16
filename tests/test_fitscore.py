"""
FitScore Test Harness
=====================
Validates the FitScore algorithm against known test cases.
Implements the exact AOE algorithm from Recommend-AdvisorCostAugmentedToBlobStorage.ps1

Source: Azure Optimization Engine by Hélder Pinto (@helderpinto)
Ported to Python for local testing.

Usage:
    python test_fitscore.py
    python test_fitscore.py -v          # verbose output
    python test_fitscore.py --case 3    # run single test case
"""

import sys
import json
from dataclasses import dataclass, field
from typing import Optional

# ═══════════════════════════════════════════════════════════════════════
#  SKU Capability Database (for offline testing)
#  Source: az vm list-skus --location eastus --output json
# ═══════════════════════════════════════════════════════════════════════

SKU_DATABASE = {
    "Standard_B2s": {
        "vCPUsAvailable": 2,
        "MemoryGB": 4,
        "MaxDataDiskCount": 4,
        "MaxNetworkInterfaces": 2,
        "UncachedDiskIOPS": 3200,
        "UncachedDiskBytesPerSecond": 48 * 1024 * 1024,  # 48 MiB/s
    },
    "Standard_D2s_v5": {
        "vCPUsAvailable": 2,
        "MemoryGB": 8,
        "MaxDataDiskCount": 4,
        "MaxNetworkInterfaces": 2,
        "UncachedDiskIOPS": 3750,
        "UncachedDiskBytesPerSecond": 85 * 1024 * 1024,  # 85 MiB/s
    },
    "Standard_D4s_v5": {
        "vCPUsAvailable": 4,
        "MemoryGB": 16,
        "MaxDataDiskCount": 8,
        "MaxNetworkInterfaces": 2,
        "UncachedDiskIOPS": 6400,
        "UncachedDiskBytesPerSecond": 145 * 1024 * 1024,  # 145 MiB/s
    },
    "Standard_D8s_v5": {
        "vCPUsAvailable": 8,
        "MemoryGB": 32,
        "MaxDataDiskCount": 16,
        "MaxNetworkInterfaces": 4,
        "UncachedDiskIOPS": 12800,
        "UncachedDiskBytesPerSecond": 290 * 1024 * 1024,  # 290 MiB/s
    },
    "Standard_D16s_v5": {
        "vCPUsAvailable": 16,
        "MemoryGB": 64,
        "MaxDataDiskCount": 32,
        "MaxNetworkInterfaces": 8,
        "UncachedDiskIOPS": 25600,
        "UncachedDiskBytesPerSecond": 580 * 1024 * 1024,  # 580 MiB/s
    },
}


# ═══════════════════════════════════════════════════════════════════════
#  Default Thresholds (from AOE)
# ═══════════════════════════════════════════════════════════════════════

DEFAULT_CPU_THRESHOLD = 30.0       # P99 CPU % — AOE default
DEFAULT_MEMORY_THRESHOLD = 50.0    # P99 Memory % — AOE default
DEFAULT_NETWORK_THRESHOLD = 750.0  # P99 Network Mbps — AOE default


# ═══════════════════════════════════════════════════════════════════════
#  Data Structures
# ═══════════════════════════════════════════════════════════════════════

@dataclass
class VMConfig:
    """Current VM configuration and observed metrics."""
    name: str
    current_sku: str
    data_disk_count: int
    nic_count: int
    p99_cpu: Optional[float] = None         # Percentage (0-100)
    p99_memory: Optional[float] = None      # Percentage (0-100)
    p99_iops: Optional[float] = None        # Total IOPS (reads + writes)
    p99_mibps: Optional[float] = None       # Total MiB/s (reads + writes)
    p99_network_mbps: Optional[float] = None  # Mbps


@dataclass
class FitScoreBreakdown:
    """Detailed breakdown of a FitScore calculation."""
    disk_count: str = ""
    nic_count: str = ""
    disk_iops: str = ""
    disk_throughput: str = ""
    cpu: str = ""
    memory: str = ""
    network: str = ""


@dataclass
class FitScoreResult:
    """Result of a FitScore calculation."""
    score: float
    breakdown: FitScoreBreakdown
    hard_violation: bool = False
    recommendation: str = ""


# ═══════════════════════════════════════════════════════════════════════
#  FitScore Calculator
#  Exact port of AOE's Recommend-AdvisorCostAugmentedToBlobStorage.ps1
# ═══════════════════════════════════════════════════════════════════════

def calculate_fitscore(
    vm: VMConfig,
    target_sku_name: str,
    cpu_threshold: float = DEFAULT_CPU_THRESHOLD,
    memory_threshold: float = DEFAULT_MEMORY_THRESHOLD,
    network_threshold: float = DEFAULT_NETWORK_THRESHOLD,
) -> FitScoreResult:
    """
    Calculate FitScore for a VM rightsizing recommendation.

    Implements the exact algorithm from AOE's PowerShell runbook:
    - Start at 5.0
    - Hard constraints (disk count, NIC count) → set to 1.0
    - Soft constraints (IOPS, throughput) → deduct 1.0 each
    - Performance metrics (CPU, memory, network) → deduct 0.5 / 0.5 / 0.1
    - Missing data → deduct 0.5

    Args:
        vm: Current VM configuration and observed P99 metrics
        target_sku_name: Target SKU name (e.g., "Standard_D4s_v5")
        cpu_threshold: P99 CPU threshold (default: 30%)
        memory_threshold: P99 Memory threshold (default: 50%)
        network_threshold: P99 Network threshold (default: 750 Mbps)

    Returns:
        FitScoreResult with score, breakdown, and recommendation
    """
    score = 5.0
    breakdown = FitScoreBreakdown()
    hard_violation = False

    # ── Look up target SKU capabilities ─────────────────────────────
    target_sku = SKU_DATABASE.get(target_sku_name)
    if target_sku is None:
        return FitScoreResult(
            score=0.0,
            breakdown=breakdown,
            hard_violation=True,
            recommendation=f"ERROR: Unknown target SKU '{target_sku_name}'"
        )

    target_max_disks = target_sku["MaxDataDiskCount"]
    target_max_nics = target_sku["MaxNetworkInterfaces"]
    target_iops = target_sku["UncachedDiskIOPS"]
    target_bytes_per_sec = target_sku["UncachedDiskBytesPerSecond"]
    target_mibps = target_bytes_per_sec / 1024 / 1024

    # ── Step 3a: Hard Constraint — Data Disk Count ──────────────────
    if target_max_disks > 0:
        if vm.data_disk_count > target_max_disks:
            score = 1.0
            hard_violation = True
            breakdown.disk_count = (
                f"FAIL: needs {vm.data_disk_count}, "
                f"target max {target_max_disks}"
            )
        else:
            breakdown.disk_count = (
                f"PASS: {vm.data_disk_count} attached, "
                f"target max {target_max_disks}"
            )
    else:
        score -= 1
        breakdown.disk_count = "UNKNOWN: target SKU disk count data unavailable"

    # Hard stop check
    if hard_violation:
        breakdown.nic_count = "SKIPPED (hard violation on disk count)"
        breakdown.disk_iops = "SKIPPED"
        breakdown.disk_throughput = "SKIPPED"
        breakdown.cpu = "SKIPPED"
        breakdown.memory = "SKIPPED"
        breakdown.network = "SKIPPED"
        return FitScoreResult(
            score=score,
            breakdown=breakdown,
            hard_violation=True,
            recommendation="Do NOT resize — hard constraint violation (disk count)"
        )

    # ── Step 3b: Hard Constraint — NIC Count ────────────────────────
    if target_max_nics > 0:
        if vm.nic_count > target_max_nics:
            score = 1.0
            hard_violation = True
            breakdown.nic_count = (
                f"FAIL: needs {vm.nic_count}, "
                f"target max {target_max_nics}"
            )
        else:
            breakdown.nic_count = (
                f"PASS: {vm.nic_count} attached, "
                f"target max {target_max_nics}"
            )
    else:
        score -= 1
        breakdown.nic_count = "UNKNOWN: target SKU NIC data unavailable"

    # Hard stop check
    if hard_violation:
        breakdown.disk_iops = "SKIPPED"
        breakdown.disk_throughput = "SKIPPED"
        breakdown.cpu = "SKIPPED"
        breakdown.memory = "SKIPPED"
        breakdown.network = "SKIPPED"
        return FitScoreResult(
            score=score,
            breakdown=breakdown,
            hard_violation=True,
            recommendation="Do NOT resize — hard constraint violation (NIC count)"
        )

    # ── Step 4a: Soft Constraint — Uncached Disk IOPS ───────────────
    if target_iops > 0:
        if vm.p99_iops is not None:
            if vm.p99_iops >= target_iops:
                score -= 1
                breakdown.disk_iops = (
                    f"FAIL: P99 IOPS {vm.p99_iops:.0f} >= "
                    f"target cap {target_iops}"
                )
            else:
                breakdown.disk_iops = (
                    f"PASS: P99 IOPS {vm.p99_iops:.0f}, "
                    f"target cap {target_iops}"
                )
        else:
            score -= 0.5
            breakdown.disk_iops = (
                f"UNKNOWN: IOPS metrics unavailable, "
                f"target cap {target_iops}"
            )
    else:
        score -= 1
        breakdown.disk_iops = "UNKNOWN: target SKU IOPS data unavailable"

    # ── Step 4b: Soft Constraint — Uncached Disk Throughput ─────────
    if target_mibps > 0:
        if vm.p99_mibps is not None:
            if vm.p99_mibps >= target_mibps:
                score -= 1
                breakdown.disk_throughput = (
                    f"FAIL: P99 throughput {vm.p99_mibps:.1f} MiBps >= "
                    f"target cap {target_mibps:.1f} MiBps"
                )
            else:
                breakdown.disk_throughput = (
                    f"PASS: P99 throughput {vm.p99_mibps:.1f} MiBps, "
                    f"target cap {target_mibps:.1f} MiBps"
                )
        else:
            score -= 0.5
            breakdown.disk_throughput = (
                f"UNKNOWN: throughput metrics unavailable, "
                f"target cap {target_mibps:.1f} MiBps"
            )
    else:
        score -= 1
        breakdown.disk_throughput = "UNKNOWN: target SKU throughput data unavailable"

    # ── Step 5a: Performance — CPU Utilization ──────────────────────
    if vm.p99_cpu is not None:
        if vm.p99_cpu >= cpu_threshold:
            score -= 0.5
            breakdown.cpu = (
                f"WARN: P99 CPU {vm.p99_cpu:.1f}% >= "
                f"threshold {cpu_threshold:.0f}%"
            )
        else:
            breakdown.cpu = (
                f"PASS: P99 CPU {vm.p99_cpu:.1f}%, "
                f"threshold {cpu_threshold:.0f}%"
            )
    else:
        breakdown.cpu = "UNKNOWN: CPU metrics unavailable"
        # No score adjustment — CPU metrics should always be available

    # ── Step 5b: Performance — Memory Utilization ───────────────────
    if vm.p99_memory is not None:
        if vm.p99_memory >= memory_threshold:
            score -= 0.5
            breakdown.memory = (
                f"WARN: P99 Memory {vm.p99_memory:.1f}% >= "
                f"threshold {memory_threshold:.0f}%"
            )
        else:
            breakdown.memory = (
                f"PASS: P99 Memory {vm.p99_memory:.1f}%, "
                f"threshold {memory_threshold:.0f}%"
            )
    else:
        score -= 0.5
        breakdown.memory = "UNKNOWN: Memory metrics unavailable (no VM Insights/AMA)"

    # ── Step 5c: Performance — Network Throughput ───────────────────
    if vm.p99_network_mbps is not None:
        if vm.p99_network_mbps >= network_threshold:
            score -= 0.1
            breakdown.network = (
                f"WARN: P99 Network {vm.p99_network_mbps:.0f} Mbps >= "
                f"threshold {network_threshold:.0f} Mbps"
            )
        else:
            breakdown.network = (
                f"PASS: P99 Network {vm.p99_network_mbps:.0f} Mbps, "
                f"threshold {network_threshold:.0f} Mbps"
            )
    else:
        breakdown.network = "UNKNOWN: Network metrics unavailable"
        # No score adjustment

    # ── Step 6: Clamp ───────────────────────────────────────────────
    score = max(0.0, score)

    # ── Step 7: Interpret ───────────────────────────────────────────
    if score >= 4.5:
        recommendation = "Safe to resize — all constraints clear or minor proximity"
    elif score >= 4.0:
        recommendation = "Likely safe — review evidence before proceeding"
    elif score >= 3.0:
        recommendation = "Caution — multiple soft constraints near limits"
    elif score >= 2.0:
        recommendation = "Risky — do not auto-resize, requires manual review"
    else:
        recommendation = "Do NOT resize — significant constraint violations"

    return FitScoreResult(
        score=score,
        breakdown=breakdown,
        hard_violation=hard_violation,
        recommendation=recommendation
    )


# ═══════════════════════════════════════════════════════════════════════
#  Test Cases
#  Based on the actual AOE algorithm thresholds:
#    CPU >= 30%    → -0.5
#    Memory >= 50% → -0.5
#    IOPS >= target cap → -1.0
#    MiBps >= target cap → -1.0
#    Network >= 750 Mbps → -0.1
#    Memory missing → -0.5
# ═══════════════════════════════════════════════════════════════════════

TEST_CASES = [
    # ── Case 1: Perfect Fit ──────────────────────────────────────────
    {
        "name": "Perfect Fit — all metrics well below thresholds",
        "vm": VMConfig(
            name="test-vm-01", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=12.0, p99_memory=25.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 5.0,
    },
    # ── Case 2: CPU threshold exceeded (>=30%) ───────────────────────
    {
        "name": "CPU threshold exceeded (P99 CPU >= 30%)",
        "vm": VMConfig(
            name="test-vm-02", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=35.0, p99_memory=25.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.5,
    },
    # ── Case 3: Memory threshold exceeded (>=50%) ────────────────────
    {
        "name": "Memory threshold exceeded (P99 Memory >= 50%)",
        "vm": VMConfig(
            name="test-vm-03", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=12.0, p99_memory=55.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.5,
    },
    # ── Case 4: Both CPU + Memory exceeded ───────────────────────────
    {
        "name": "CPU + Memory both exceeded",
        "vm": VMConfig(
            name="test-vm-04", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=35.0, p99_memory=55.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.0,
    },
    # ── Case 5: Disk IOPS exceeds target SKU cap ────────────────────
    {
        "name": "Disk IOPS exceeds target SKU cap (P99 >= 6400)",
        "vm": VMConfig(
            name="test-vm-05", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=12.0, p99_memory=25.0,
            p99_iops=6500, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.0,  # -1.0 for IOPS
    },
    # ── Case 6: Hard Constraint — Disk Count ─────────────────────────
    {
        "name": "Hard constraint violation: disk count (7 > max 4)",
        "vm": VMConfig(
            name="test-vm-06", current_sku="Standard_D8s_v5",
            data_disk_count=7, nic_count=1,
            p99_cpu=12.0, p99_memory=25.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D2s_v5",
        "expected_score": 1.0,
    },
    # ── Case 7: Hard Constraint — NIC Count ──────────────────────────
    {
        "name": "Hard constraint violation: NIC count (4 > max 2)",
        "vm": VMConfig(
            name="test-vm-07", current_sku="Standard_D8s_v5",
            data_disk_count=1, nic_count=4,
            p99_cpu=12.0, p99_memory=25.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_B2s",
        "expected_score": 1.0,
    },
    # ── Case 8: Missing Memory Metrics ───────────────────────────────
    {
        "name": "Missing memory metrics (no VM Insights/AMA)",
        "vm": VMConfig(
            name="test-vm-08", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=12.0, p99_memory=None,  # Missing
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.5,  # -0.5 for missing memory
    },
    # ── Case 9: Multiple soft constraint violations ──────────────────
    {
        "name": "Multiple soft violations (CPU + Memory + IOPS + Network)",
        "vm": VMConfig(
            name="test-vm-09", current_sku="Standard_D8s_v5",
            data_disk_count=3, nic_count=1,
            p99_cpu=45.0, p99_memory=65.0,
            p99_iops=7000, p99_mibps=30.0, p99_network_mbps=800.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 2.9,  # -0.5 CPU -0.5 Mem -1.0 IOPS -0.1 Net = -2.1
    },
    # ── Case 10: All soft constraints exceeded ───────────────────────
    {
        "name": "All soft constraints exceeded",
        "vm": VMConfig(
            name="test-vm-10", current_sku="Standard_D16s_v5",
            data_disk_count=3, nic_count=1,
            p99_cpu=50.0, p99_memory=70.0,
            p99_iops=4000, p99_mibps=90.0, p99_network_mbps=800.0,
        ),
        "target_sku": "Standard_D2s_v5",
        "expected_score": 1.9,  # -0.5 CPU -0.5 Mem -1.0 IOPS -1.0 MiBps(90>=85) -0.1 Net = -3.1
    },
    # ── Case 11: Hard + Soft Combined (hard wins) ────────────────────
    {
        "name": "Hard constraint overrides all soft violations",
        "vm": VMConfig(
            name="test-vm-11", current_sku="Standard_D8s_v5",
            data_disk_count=7, nic_count=1,
            p99_cpu=90.0, p99_memory=92.0,
            p99_iops=4500, p99_mibps=180.0, p99_network_mbps=5000.0,
        ),
        "target_sku": "Standard_D2s_v5",
        "expected_score": 1.0,
    },
    # ── Case 12: Boundary — exactly at CPU threshold ─────────────────
    {
        "name": "Boundary: CPU exactly at 30% triggers deduction (>=)",
        "vm": VMConfig(
            name="test-vm-12", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=30.0, p99_memory=25.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.5,  # AOE uses >= so 30.0 triggers
    },
    # ── Case 13: Boundary — CPU just below threshold ─────────────────
    {
        "name": "Boundary: CPU at 29.9% does NOT trigger deduction",
        "vm": VMConfig(
            name="test-vm-13", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=29.9, p99_memory=25.0,
            p99_iops=1200, p99_mibps=30.0, p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 5.0,
    },
    # ── Case 14: Missing all metrics ─────────────────────────────────
    {
        "name": "Missing all performance metrics",
        "vm": VMConfig(
            name="test-vm-14", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=None, p99_memory=None,
            p99_iops=None, p99_mibps=None, p99_network_mbps=None,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 3.5,  # -0.5 IOPS -0.5 MiBps -0.5 Memory = -1.5
    },
    # ── Case 15: Disk throughput exceeds target ──────────────────────
    {
        "name": "Disk throughput exceeds target SKU cap",
        "vm": VMConfig(
            name="test-vm-15", current_sku="Standard_D8s_v5",
            data_disk_count=2, nic_count=1,
            p99_cpu=12.0, p99_memory=25.0,
            p99_iops=1200, p99_mibps=150.0,  # D4s_v5 cap = 145 MiB/s
            p99_network_mbps=100.0,
        ),
        "target_sku": "Standard_D4s_v5",
        "expected_score": 4.0,  # -1.0 for throughput
    },
]


# ═══════════════════════════════════════════════════════════════════════
#  Test Runner
# ═══════════════════════════════════════════════════════════════════════

def run_tests(verbose: bool = False, single_case: int = None) -> bool:
    """Run all FitScore test cases and report results."""
    passed = 0
    failed = 0
    total = len(TEST_CASES)

    print()
    print("=" * 70)
    print("  FitScore Test Harness")
    print("  Algorithm: AOE (Recommend-AdvisorCostAugmentedToBlobStorage.ps1)")
    print(f"  Thresholds: CPU>={DEFAULT_CPU_THRESHOLD}%, "
          f"Memory>={DEFAULT_MEMORY_THRESHOLD}%, "
          f"Network>={DEFAULT_NETWORK_THRESHOLD} Mbps")
    print("=" * 70)
    print()

    cases_to_run = TEST_CASES
    if single_case is not None:
        if 1 <= single_case <= len(TEST_CASES):
            cases_to_run = [TEST_CASES[single_case - 1]]
        else:
            print(f"Error: Case {single_case} not found (valid: 1-{len(TEST_CASES)})")
            return False

    for i, tc in enumerate(cases_to_run, 1):
        case_num = single_case if single_case else i
        result = calculate_fitscore(tc["vm"], tc["target_sku"])
        expected = tc["expected_score"]
        actual = round(result.score, 1)
        match = abs(actual - expected) < 0.01

        status = "✅ PASS" if match else "❌ FAIL"
        if match:
            passed += 1
        else:
            failed += 1

        print(f"  Case {case_num:2d}: {status}  "
              f"[{actual:.1f} {'==' if match else '!='} {expected:.1f}]  "
              f"{tc['name']}")

        if verbose or not match:
            b = result.breakdown
            print(f"           SKU: {tc['vm'].current_sku} → {tc['target_sku']}")
            print(f"           Disk Count:  {b.disk_count}")
            print(f"           NIC Count:   {b.nic_count}")
            print(f"           Disk IOPS:   {b.disk_iops}")
            print(f"           Disk MiBps:  {b.disk_throughput}")
            print(f"           CPU:         {b.cpu}")
            print(f"           Memory:      {b.memory}")
            print(f"           Network:     {b.network}")
            print(f"           Verdict:     {result.recommendation}")
            print()

    print()
    print("-" * 70)
    total_run = passed + failed
    print(f"  Results: {passed}/{total_run} passed, {failed} failed")
    if failed == 0:
        print("  🎉 All tests passed!")
    else:
        print(f"  ⚠️  {failed} test(s) failed — review above for details")
    print("-" * 70)
    print()

    return failed == 0


# ═══════════════════════════════════════════════════════════════════════
#  CLI Entry Point
# ═══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    single_case = None

    if "--case" in sys.argv:
        idx = sys.argv.index("--case")
        if idx + 1 < len(sys.argv):
            try:
                single_case = int(sys.argv[idx + 1])
            except ValueError:
                print("Error: --case requires an integer")
                sys.exit(1)

    success = run_tests(verbose=verbose, single_case=single_case)
    sys.exit(0 if success else 1)
