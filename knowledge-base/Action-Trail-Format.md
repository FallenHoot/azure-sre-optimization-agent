# Action Trail Format

## Purpose

Every specialist subagent MUST save a structured action trail document alongside its scan report. Action trails provide structured observability into agent execution — what tools were called, what succeeded, what failed, how long it took, and how much of the budget was consumed. The orchestrator aggregates these into a Platform Health section.

This is inspired by the "Action Trails" concept from the Cloudgeni Infrastructure Agents Guide (Chapter 9: Observability & Audit). Since we run on the managed SRE Agent platform (no custom OpenTelemetry), action trails are persisted as knowledge base documents via `UploadKnowledgeDocument`.

---

## Document Naming Convention

Each specialist saves its action trail with this title pattern:

```
Action-Trail-{Domain}-YYYY-MM-DD
```

Examples:
- `Action-Trail-Compute-2026-04-28`
- `Action-Trail-Storage-2026-04-28`
- `Action-Trail-Orchestrator-2026-04-28`

---

## Action Trail Schema

The action trail document is a structured markdown document with embedded data tables. Use this exact format so the orchestrator can parse it consistently.

### Header Section

```markdown
## Action Trail — {Agent Name}
- **Scan date:** YYYY-MM-DD HH:MM UTC
- **Agent:** {Compute|Storage|Network|PaaS|Governance}-Optimization-Specialist
- **Autonomy tier:** {0|1|2|3|4} (tier used during this scan)
- **Subscriptions scanned:** {sub-1-id}, {sub-2-id}
- **Scan duration:** {N} minutes
- **Scan outcome:** {COMPLETE|PARTIAL|FAILED}
```

### Budget Usage Section

```markdown
### Budget Usage
| Metric | Used | Limit | % Used |
|---|---|---|---|
| Tool calls | 87 | 200 | 44% |
| Duration (minutes) | 32 | 55 | 58% |
| Consecutive failures | 1 | 3 | 33% |
```

Flag any metric that exceeds 80% as a warning. If any metric hits 100%, the scan should have stopped and `scan_outcome` should be `PARTIAL`.

### Resource Summary Section

```markdown
### Resource Summary
| Metric | Count |
|---|---|
| Resources discovered | 47 |
| Resources analyzed | 45 |
| Resources with findings | 12 |
| Resources skipped (failures) | 2 |
| Recommendations generated | 14 |
| Estimated monthly savings | $1,247 |
```

### Tool Call Summary Section

```markdown
### Tool Call Summary
| Tool | Calls | Successes | Failures | Avg Duration |
|---|---|---|---|---|
| RunAzCliReadCommands | 52 | 50 | 2 | ~3s |
| ExecutePythonCode | 15 | 15 | 0 | ~1s |
| SearchMemory | 4 | 4 | 0 | ~1s |
| GetAzCliHelp | 1 | 1 | 0 | ~2s |
| UploadKnowledgeDocument | 2 | 2 | 0 | ~2s |
```

### Failure Log Section

Record every failure, classified using the categories from **Failure-Taxonomy.md**:

```markdown
### Failures
| # | Resource | Category | Tool | Operation | Detail | Retried | Impact |
|---|---|---|---|---|---|---|---|
| 1 | /subscriptions/.../vm-web-01 | DATA_MISSING | RunAzCliReadCommands | az monitor query (memory) | No AMA agent installed | No | FitScore without memory dimension |
| 2 | /subscriptions/.../vm-batch-03 | TRANSIENT | RunAzCliReadCommands | az monitor query (CPU) | 429 throttled | Yes (succeeded) | None — retry succeeded |
```

If there are zero failures, write: `### Failures\nNone.`

### Key Decisions Section

Record significant analytical decisions the agent made during the scan:

```markdown
### Key Decisions
| # | Resource | Decision | Rationale |
|---|---|---|---|
| 1 | vm-oversized-v3 | Recommended D4s_v5 over D4as_v5 | D4as_v5 lacks PremiumIO; VM has Premium_LRS disk |
| 2 | vm-batch-pool | Flagged for Spot eligibility | VMSS with 5 instances behind LB, stateless workload pattern |
| 3 | disk-archive-logs | Recommended Cool tier over Archive | Access pattern shows monthly reads; Archive has hours-long rehydration |
```

This section is optional for simple scans but REQUIRED when the agent chose between multiple alternatives or made judgment calls.

---

## Orchestrator Aggregation

The orchestrator collects all specialist action trails and produces a **Platform Health** section in the executive summary:

```markdown
## Platform Health Summary

### Scan Completion
| Specialist | Outcome | Duration | Budget Used | Failures |
|---|---|---|---|---|
| Compute | COMPLETE | 32 min | 44% | 2 (1 DATA_MISSING, 1 TRANSIENT) |
| Storage | COMPLETE | 28 min | 38% | 0 |
| Network | COMPLETE | 15 min | 22% | 1 (1 PERMANENT) |
| PaaS | COMPLETE | 22 min | 35% | 0 |
| Governance | PARTIAL | 55 min | 100% (duration) | 4 (3 TRANSIENT, 1 BUDGET) |

### Failure Trends (vs. prior week)
| Category | This Week | Last Week | Trend |
|---|---|---|---|
| DATA_MISSING | 3 | 5 | ↓ Improving |
| TRANSIENT | 4 | 2 | ↑ Watch — possible throttling |
| AUTH_EXPIRED | 0 | 0 | — Stable |

### Escalations (trend-aware)
- ⚠️ vm-legacy-01: DATA_MISSING for 4 consecutive weeks → **Escalate: AMA deployment needed**
- ⚠️ Governance specialist hit budget limit 2 consecutive weeks → **Review budget: may need increase**
```

---

## Integration with Specialist Workflows

Each specialist adds a **final step** to their workflow:

> **Step N+1 — SAVE ACTION TRAIL**
> Using `ExecutePythonCode`, compile the action trail from tracked data
> accumulated during the scan. Save via `UploadKnowledgeDocument` with
> title `Action-Trail-{Domain}-YYYY-MM-DD`.

The agent should track tool calls, failures, and timing throughout execution, then compile and save the trail as the very last step (after saving the scan report).
