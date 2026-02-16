# Workload Pattern Identification

## Purpose

This document describes how the AI agent can identify workload patterns from time-series metric data and use those patterns to improve the quality of optimization recommendations. This is a **new capability that the Azure Optimization Engine (AOE) does not have** — AOE uses only P99 aggregation over a lookback period, which collapses all temporal context into a single number.

> **🆕 New Capability:** Workload pattern detection is an enhancement unique to this SRE Agent implementation. AOE by Hélder Pinto does not perform pattern analysis — it relies solely on P99 (or percentile) aggregation. By understanding *how* a workload uses resources over time, the agent can make smarter, safer recommendations.

---

## Why Pattern Detection Matters

### The Problem with P99 Alone

Consider two VMs, both showing CPU P99 = 25% over 7 days:

**VM A — Steady State:**
```
CPU: 22%, 24%, 23%, 25%, 24%, 23%, 22%, 24%, 25%, 23% ...
Pattern: Flat line around 23-25%
```

**VM B — Burst:**
```
CPU: 2%, 3%, 1%, 2%, 95%, 2%, 1%, 3%, 2%, 98%, 1%, 2% ...
Pattern: Mostly idle with periodic spikes to 95-98%
```

Both have P99 ≈ 25% when calculated over hourly bins, but:
- **VM A** can safely be resized aggressively — it's truly underutilized
- **VM B** should NOT be resized — it needs its current capacity for burst handling

AOE would recommend resizing both. Pattern detection allows the agent to differentiate them.

---

## Pattern Types

### 1. Steady State

**Characteristics:**
- CPU/memory utilization stays within a narrow band (±10% of mean)
- Low coefficient of variation (CV < 0.3)
- No significant time-of-day or day-of-week correlation

**Visual Profile:**
```
100% |
 75% |
 50% |
 25% |████████████████████████████████████
  0% |____________________________________
      Mon  Tue  Wed  Thu  Fri  Sat  Sun
```

**Recommendation Impact:**
- ✅ Can resize **aggressively** — this workload is predictable
- Use P99 as the capacity target with minimal headroom (10%)
- High confidence in savings estimate

### 2. Burst

**Characteristics:**
- Long periods of low utilization punctuated by short spikes
- High coefficient of variation (CV > 1.0)
- Spikes may be random or triggered by events
- P99 is misleading because hourly binning smooths out short spikes

**Visual Profile:**
```
100% |        █           █       █
 75% |        █           █       █
 50% |        █           █       █
 25% |        █           █       █
  0% |████████ ███████████ ███████ ████
      Mon  Tue  Wed  Thu  Fri  Sat  Sun
```

**Recommendation Impact:**
- ⚠️ Resize with **extreme caution** — the workload needs burst capacity
- Add 30-50% headroom above P99 when sizing
- Consider recommending auto-scaling instead of static resize
- Lower FitScore by 1 point for burst workloads
- Flag as "Burst Pattern Detected" in risk assessment

### 3. Batch

**Characteristics:**
- Scheduled high-utilization windows (e.g., nightly ETL, hourly data processing)
- Clear on/off pattern with high utilization during batch windows
- Strong time-of-day correlation
- Utilization during off-hours is near zero

**Visual Profile:**
```
100% | ██  ██  ██  ██  ██  ██  ██
 75% | ██  ██  ██  ██  ██  ██  ██
 50% | ██  ██  ██  ██  ██  ██  ██
 25% | ██  ██  ██  ██  ██  ██  ██
  0% |█  ██  ██  ██  ██  ██  ██  █
      Mon  Tue  Wed  Thu  Fri  Sat  Sun
      (2AM-4AM batch window each night)
```

**Recommendation Impact:**
- 🔄 Recommend **scale-out or auto-start/stop** instead of resize
- Consider Azure Automation runbooks for start/stop scheduling
- Savings come from compute deallocation during off-hours, not from smaller SKU
- Calculate savings based on off-hours ratio: `savings = hourly_rate × off_hours_per_month`

### 4. Cyclical

**Characteristics:**
- Regular daily pattern (high during business hours, low overnight)
- Or regular weekly pattern (high weekdays, low weekends)
- Autocorrelation at 24-hour or 168-hour (7-day) lags is significant
- Mean utilization varies predictably by time of day/week

**Visual Profile:**
```
100% |
 75% |  ████    ████    ████    ████
 50% | █    █  █    █  █    █  █    █
 25% |█      ██      ██      ██      █
  0% |____________________________________
      Mon  Tue  Wed  Thu  Fri  Sat  Sun
      (Business hours pattern)
```

**Recommendation Impact:**
- 📊 Size for the peak cycle, but consider auto-scaling for off-peak
- P99 is a reasonable sizing target since the peak is sustained
- Recommend dev/test shutdown for non-production cyclical workloads
- Calculate off-peak savings separately

### 5. Growing

**Characteristics:**
- Clear upward trend in utilization over the lookback period
- Linear or exponential growth in resource consumption
- The workload may currently be underutilized but won't be for long

**Visual Profile:**
```
100% |                               ███
 75% |                         ██████
 50% |                  ███████
 25% |          ████████
  0% |██████████____________________________
      Week 1  Week 2  Week 3  Week 4
```

**Recommendation Impact:**
- 🚫 Do NOT recommend downsizing — the workload is growing into its current capacity
- Flag as "Growing Pattern" — no action needed now
- Set a reminder to re-evaluate in 30 days
- If growth rate continues, may need to recommend **upsizing** instead

---

## Pattern Detection Methods

### Statistical Approach

For each VM's hourly CPU time series over 30 days (720 data points):

#### Step 1: Basic Statistics

```python
import numpy as np

mean = np.mean(cpu_values)
std = np.std(cpu_values)
cv = std / mean  # Coefficient of Variation
median = np.median(cpu_values)
p99 = np.percentile(cpu_values, 99)
p5 = np.percentile(cpu_values, 5)
iqr = np.percentile(cpu_values, 75) - np.percentile(cpu_values, 25)
```

#### Step 2: Pattern Classification Rules

| Pattern | CV | Trend Slope | Autocorrelation (24h) | P99/Mean Ratio | Additional Criteria |
|---|---|---|---|---|---|
| Steady State | < 0.3 | Near zero (|slope| < 0.1%/day) | Low (< 0.3) | < 1.5 | — |
| Burst | > 1.0 | Any | Low (< 0.3) | > 3.0 | Spike count > 5 in 7 days |
| Batch | > 0.5 | Near zero | High (> 0.6) at 24h | > 2.0 | Clear on/off pattern |
| Cyclical | 0.3–0.7 | Near zero | High (> 0.5) at 24h or 168h | 1.5–3.0 | Smooth daily/weekly wave |
| Growing | Any | Positive (slope > 0.5%/day) | Any | Any | Sustained upward trend |

#### Step 3: Trend Detection

```python
from scipy import stats

hours = np.arange(len(cpu_values))
slope, intercept, r_value, p_value, std_err = stats.linregress(hours, cpu_values)

# slope > 0.02 per hour ≈ 0.5% per day → Growing pattern
is_growing = slope > 0.02 and p_value < 0.05
```

#### Step 4: Autocorrelation

```python
from statsmodels.tsa.stattools import acf

# Calculate autocorrelation at lag=24 (daily) and lag=168 (weekly)
autocorr = acf(cpu_values, nlags=168)
daily_autocorr = autocorr[24]
weekly_autocorr = autocorr[168]

is_cyclical = daily_autocorr > 0.5 or weekly_autocorr > 0.5
```

#### Step 5: Spike Detection

```python
# Count hours where CPU > 3 standard deviations above mean
spike_threshold = mean + 3 * std
spike_count = np.sum(cpu_values > spike_threshold)

is_bursty = spike_count > 5 and cv > 1.0
```

### Time-Series KQL Query for Pattern Detection

Collect hourly data over 30 days for pattern analysis:

```kql
let lookback = 30d;
Perf
| where TimeGenerated > ago(lookback)
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize
    avgCpu = avg(CounterValue),
    maxCpu = max(CounterValue),
    minCpu = min(CounterValue),
    stdevCpu = stdev(CounterValue),
    p99Cpu = percentile(CounterValue, 99),
    p50Cpu = percentile(CounterValue, 50)
    by Computer, bin(TimeGenerated, 1h)
| order by Computer asc, TimeGenerated asc
```

This returns the hourly time series needed for the statistical analysis above.

---

## Integration with FitScore

Pattern detection should influence the FitScore calculation:

| Pattern | FitScore Adjustment | Rationale |
|---|---|---|
| Steady State | No adjustment | Standard P99 analysis is reliable |
| Burst | −1.0 from calculated FitScore | Burst workloads need headroom; penalize aggressive sizing |
| Batch | −0.5 from calculated FitScore | Batch windows need full capacity; slight penalty |
| Cyclical | No adjustment | P99 captures peak cycle adequately |
| Growing | Set FitScore to 1.0 (do not resize down) | Growing workloads should not be downsized |

**Example:**
- VM has calculated FitScore of 4.5 (resize looks great based on P99)
- Pattern detection identifies it as Burst
- Adjusted FitScore: 4.5 − 1.0 = 3.5
- This moves it from High severity to Medium severity, reducing false positive risk

---

## Integration with Threshold Overrides

When pattern detection identifies a burst or batch workload, the agent should:

1. **Burst workloads:** Effectively increase the CPU threshold by 50% (e.g., from 30% to 45%) to account for needed headroom
2. **Batch workloads:** Evaluate metrics only during the batch window for sizing, and off-window for shutdown savings
3. **Growing workloads:** Ignore current underutilization; do not recommend downsizing

These adjustments happen automatically — no tag-based override is needed.

---

## Tag-Based Workload Classification

Teams can proactively classify their workloads using tags, which supplements or overrides the automated detection:

| Tag | Values | Effect |
|---|---|---|
| `aoe:workloadType` | `steady`, `burst`, `batch`, `cyclical`, `growing` | Override the automatically detected pattern |
| `aoe:batchWindow` | `02:00-04:00 UTC` | Define the batch processing window for batch workloads |
| `aoe:peakHours` | `08:00-18:00 UTC` | Define peak hours for cyclical workloads |

**Priority:** Tag-based classification takes precedence over automated detection, since the team knows their workload best.

---

## Visualization with ExecutePythonCode

When generating reports or investigating specific resources, use the `ExecutePythonCode` tool to visualize the workload pattern:

```python
# Example: Visualize CPU time series with pattern annotation
plot_data = {
    "title": f"CPU Utilization Pattern — {vm_name}",
    "x_label": "Time",
    "y_label": "CPU %",
    "series": [
        {
            "name": "CPU P99 (hourly)",
            "data": hourly_cpu_values,
            "timestamps": hourly_timestamps
        }
    ],
    "annotations": [
        {
            "label": f"Pattern: {detected_pattern}",
            "position": "top-right"
        },
        {
            "label": f"P99: {p99_value}%",
            "y_value": p99_value,
            "style": "horizontal-line"
        },
        {
            "label": f"Threshold: {threshold}%",
            "y_value": threshold,
            "style": "horizontal-line-dashed"
        }
    ]
}
```

This visualization helps SRE teams understand why a recommendation was (or wasn't) made, and builds trust in the AI agent's decisions.

---

## Confidence Levels

Pattern detection should report a confidence level:

| Confidence | Criteria | Action |
|---|---|---|
| **High** (> 80%) | Clear pattern with strong statistical signals; 30+ days of data | Apply pattern adjustment to FitScore |
| **Medium** (50–80%) | Pattern detected but with some ambiguity; 14–30 days of data | Apply pattern adjustment with reduced weight (50%) |
| **Low** (< 50%) | Insufficient data or ambiguous pattern; < 14 days of data | Do NOT apply pattern adjustment; fall back to standard P99 |

---

## Pattern Detection Limitations

- **Data requirement:** Reliable pattern detection needs at least 14 days of hourly data (336 data points). 30 days (720 data points) is recommended.
- **Compute cost:** Pattern analysis is more expensive than simple P99 calculation. Run it selectively for VMs that are near the threshold boundary.
- **False patterns:** Short-term anomalies (one-time migrations, incidents) can create false patterns. Consider filtering out known anomaly periods.
- **Multi-metric patterns:** Currently analyzes CPU independently. Future enhancement: correlate CPU + memory + disk patterns for richer understanding.

---

## Summary: AOE vs SRE Agent Comparison

| Capability | AOE | SRE Agent (This Project) |
|---|---|---|
| P99 aggregation | ✅ | ✅ |
| Pattern detection | ❌ | ✅ **New** |
| Burst workload handling | ❌ (may false-positive) | ✅ (adds headroom, reduces FitScore) |
| Batch workload optimization | ❌ | ✅ (recommends schedule-based savings) |
| Growth trend detection | ❌ | ✅ (prevents premature downsizing) |
| Time-series visualization | ❌ | ✅ (ExecutePythonCode for charting) |
| Confidence reporting | ❌ | ✅ (High/Medium/Low confidence) |
