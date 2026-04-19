# Skillable AI Learnings Applied to Azure SRE Optimization Engine

## Executive Summary
Skillable AI's approach to automation, validation, dynamic guidance, and learner engagement can inform the design of your Azure SRE Optimization subagents. Key concepts to adopt include **automated assessment frameworks**, **structured guidance patterns**, **vision-based validation**, and **extensible architecture**.

---

## 1. Skillable AI Capabilities & SRE Parallels

### Skillable Concept: Scripting Co-Pilot
**What it does:** Generative AI for automated activity scripts; reduces manual effort, accelerates build time.

**SRE Parallel:** **Auto-Script Generation for Remediation**
- Generate cloud remediation scripts (Bicep, PowerShell, Bash) from FitScore findings.
- Reduce manual SRE effort in translating recommendations to executable deployments.
- Example: "Based on FitScore analysis, generate the Bicep module to migrate VM from D8s_v3 → D4s_v5"

**Implementation:**
- Add tool: `GenerateRemediationScript` to subagent.yaml
- Input: resource ID, current SKU, target SKU, constraints
- Output: executable Bicep/PowerShell template with validation checks

---

### Skillable Concept: AI Vision Activities
**What it does:** Computer vision validates what a user sees/does on screen; bypasses traditional script checks.

**SRE Parallel:** **Visual Cost Validation & Screenshot Audit**
- Capture Azure Portal screenshots post-migration to validate UI state changes (e.g., VM SKU changed, alerts configured).
- Detect configuration drift by comparing expected vs. actual portal screenshots.
- Automated audit trail: "Prove the change was applied" without relying solely on API calls.

**Implementation:**
- Add tool: `CaptureAndValidatePortalState` to detect:
  - VM size change verification
  - Spot VM enablement confirmation
  - Advisor recommendation acknowledgment
  - High-availability zone assignment

---

### Skillable Concept: Structured Guidance (AI Menu)
**What it does:** Embedded topic-based prompts: "Teach me," "Show me," "Quiz me," "Find Resources."

**SRE Parallel:** **Multi-Mode Optimization Reporting**
Extend your report output with structured guidance options:
- **"Teach me"** → Explain FitScore dimensions, why constraint failed, best practices
- **"Show me"** → Step-by-step remediation workflow (pre-flight checks → deploy → validation)
- **"Quiz me"** → Test SRE knowledge: "Why is this VM CPU-bound?" (self-assessment)
- **"Find Resources"** → Links to MS Learn, KB docs, Advisor recommendations

**Implementation:**
- Add report section: "💡 Guidance Options"
```
| Finding | Teach Me | Show Me | Quiz Me | Resources |
|---------|----------|---------|---------|-----------|
| FitScore 3.2 | Why did CPU → warn? | Deploy steps | Test your knowledge | SKU best practices |
```

---

### Skillable Concept: AI Chat & Real-Time Support
**What it does:** Topic-focused chat inside instructions; learners ask questions in scope.

**SRE Parallel:** **Inline Agent Q&A in Reports**
- Embed a scoped chat interface in the persisted report (or chat output).
- SREs ask: "Why can't I use F16s_v2?" → Agent responds: "F-family is retired; recommend E16s_v5."
- Maintains context: all questions scoped to the current scan, resources, constraints.

**Implementation:**
- Extend `UploadKnowledgeDocument` output to include a Q&A section:
```yaml
Questions Addressed in This Scan:
- "Why not resize VM-01 to E4s_v5?" 
  Answer: 2 Premium_LRS disks; E4 doesn't support PremiumIO. Recommend D4s_v5 instead.
```

---

### Skillable Concept: Practice Generator (Learner-Led)
**What it does:** Learners create additional scenarios during a session; reinforce skills, encourage experimentation.

**SRE Parallel:** **What-If Analysis Tool**
- SREs run "practice" scenarios: "Show me the savings if I migrate 5 more VMs to Spot."
- Non-destructive sandbox simulations.
- Hypothesis testing: "What if lookback = 30 days instead of 7?"

**Implementation:**
- Add tool: `RunWhatIfSimulation`
- Input: original finding, parameter changes (e.g., SKU, lookback, VMSS instance count)
- Output: side-by-side FitScore & cost comparison

---

### Skillable Concept: AI Generated Content Tags
**What it does:** Structured tags (`ai teach`, `ai show`, `ai quiz`, `ai resources`) auto-generate content.

**SRE Parallel:** **Metadata-Driven Report Templates**
- Tag each recommendation with structured metadata:
```yaml
recommendation:
  id: REC-001
  vm_name: prod-sql-01
  action: resize
  severity: High
  
  ai_teach: >
    Why this recommendation: P99 Memory is 45% vs target 50%. 
    Current D8s_v5 (32 GB) → D6s_v5 (24 GB) frees $120/mo.
    
  ai_show: >
    Step 1: Deallocate VM
    Step 2: Update SKU via Portal or CLI
    Step 3: Start VM & validate
    
  ai_quiz: "What's the max network throughput for D6s_v5?" (Answer: 12500 Mbps)
  
  ai_resources:
    - https://learn.microsoft.com/azure/virtual-machines/sizes-previous-gen
    - KB: SKU-Constraint-Rules.md
```

---

## 2. Architectural Patterns from Skillable AI

### Pattern 1: Multi-Model Support (BYO Model)
**Skillable's approach:** Supports both Skillable-provided models and Bring Your Own (BYO).

**SRE Application:**
- Support multiple optimization backends:
  - Azure Advisor (default)
  - Custom ML model (e.g., trained on org's workload patterns)
  - Third-party cost optimizer
- Configuration:
```yaml
optimization_backend: "azure-advisor"  # or "custom-ml" or "third-party-optimizer"
model_config:
  provider: "azure"
  api_version: "2023-04-01"
  custom_weights:
    fitscore: 0.6
    cost: 0.3
    risk: 0.1
```

---

### Pattern 2: Usage Tracking & Metering
**Skillable's approach:** Tracks usage for Skillable-provided models; BYO has no Skillable billing.

**SRE Application:**
- Add audit logging to track agent executions:
```yaml
audit_metrics:
  - vm_scans_per_month
  - fitscore_calculations
  - api_calls_to_advisor
  - remediation_scripts_generated
  - cost_per_recommendation
```
- Support hybrid: free tier (basic scan), premium (advanced features)

---

### Pattern 3: Flexible Authoring + Runtime Separation
**Skillable's approach:** Authoring tools (Studio) vs. Runtime (Lab Client); clear separation.

**SRE Application:**
```
Authoring Layer:
├── KB docs (FitScore-Methodology.md, SKU-Constraint-Rules.md)
├── Agent config (subagent.yaml with system_prompt)
└── Validation rules (hard constraints, soft deductions)

Runtime Layer:
├── Compute-Optimization-Specialist agent
├── Real-time Azure API calls
└── Dynamic report generation
```

---

## 3. Reporting Enhancement Strategy

### Current State (Skillable-Inspired Gap Analysis)

| Aspect | Current | Skillable Inspiration | Enhancement |
|--------|---------|----------------------|--------------|
| **Content** | Action table | Teach/Show/Quiz/Resources tags | Add guidance metadata to each rec |
| **Interactivity** | Static report | Embedded Q&A chat | Link to FAQs, auto-answer common Qs |
| **Validation** | API-based | Visual + API checks | Screenshot audit trail for drift detection |
| **Extensibility** | Fixed KB docs | BYO model support | Support custom optimization engines |
| **Learner Support** | Report only | Structured guidance | Multi-mode output (teach/show/do) |
| **Practice** | Single scan | Scenario generation | What-If simulator for hypothetical changes |

---

## 4. Proposed Subagent Enhancements

### Enhancement 1: Report Metadata Tags
**File to modify:** `subagents/compute-optimization/subagent.yaml`

Add to system_prompt:
```yaml
## AI-Assisted Reporting (Skillable-Inspired)
Each recommendation in persisted report includes:
- **ai_teach**: Plain-language explanation of WHY (metric, threshold, impact)
- **ai_show**: Step-by-step remediation workflow
- **ai_quiz**: Self-assessment question (SRE validates understanding)
- **ai_resources**: Links to relevant docs, Learn articles, KB

Example:
recommendation:
  id: REC-001
  vm_name: prod-sql-01
  current_sku: D8s_v5
  target_sku: D6s_v5
  fitscore: 4.1
  monthly_savings: $120
  
  ai_teach: |
    Why downsize D8s_v5 → D6s_v5?
    - Memory P99: 45% of 32 GB = 14.4 GB available
    - Target threshold: 50% = 16 GB required
    - D6s_v5 has 24 GB (✓ passes safety margin)
    - No hard constraint violations
    - Saves 25% compute cost ($120/mo)
  
  ai_show: |
    1. Stop VM (downtime ~5 min)
    2. az vm deallocate --resource-group RG --name prod-sql-01
    3. az vm resize --resource-group RG --name prod-sql-01 --size Standard_D6s_v5
    4. Start VM: az vm start --resource-group RG --name prod-sql-01
    5. Validate: Check Portal → Advisor → recompute recommendations
  
  ai_quiz: "What's the max data disk count for D6s_v5?" (Answer: 32)
  
  ai_resources:
    - https://learn.microsoft.com/azure/virtual-machines/sizes-compute#ddsv5-series
    - KB: SKU-Constraint-Rules.md
    - Advisor: <recommendation_id_link>
```

---

### Enhancement 2: What-If Simulation Tool
**New tool to add:** `RunWhatIfSimulation`

```yaml
tools:
  - RunAzCliReadCommands
  - ExecutePythonCode
  - UploadKnowledgeDocument
  - RunWhatIfSimulation  # NEW: hypothetical analysis
  
RunWhatIfSimulation parameters:
  - baseline_report_id: "Compute-Optimization-Report-2026-02-27"
  - scenario_changes:
      lookback_days: 30  # vs. baseline 7
      target_sku_override: "D4s_v5"  # override recommendation
      spot_eligibility_strict: true  # apply stricter Spot rules
  
Output:
  - scenario_fitscore: 4.3
  - scenario_monthly_savings: $245
  - delta_vs_baseline: +$35/mo (+$420/yr)
  - risk_change: "Low → Medium" (if spot_strict enabled)
```

---

### Enhancement 3: Dual Output (Teach/Show/Do)
**Modify report format to support modes:**

```yaml
reporting_modes:
  concise:
    output: "Action table only (current behavior)"
  
  detailed:
    output: "Action table + FitScore breakdown"
  
  interactive:  # NEW
    output: "Action table + guidance options"
    guidance:
      - teach_me: Explain FitScore, thresholds, constraints
      - show_me: Step-by-step remediation
      - quiz_me: Self-assessment Q&A
      - find_resources: Relevant docs
```

**Report section example:**
```markdown
## Compute Optimization — 2026-02-27

| # | VM | Current → Target | FitScore | $/mo | Guidance |
|---|-----|------------------|----------|------|----------|
| 1 | prod-sql-01 | D8s_v5→D6s_v5 | 4.1 ✅ | $120 | [Teach](🔗) [Show](🔗) [Quiz](🔗) |

**[Teach Me]** Why downsize? Memory P99 is 45%; target supports 50% threshold...
**[Show Me]** Step-by-step: deallocate → resize → validate...
**[Quiz Me]** Test your knowledge: What's the max throughput for D6s_v5?
**[Find Resources]** SKU docs, MS Learn, Advisor recommendation...
```

---

## 5. Implementation Roadmap

### Phase 1: Metadata Tags (1-2 sprints)
- [ ] Add `ai_teach`, `ai_show`, `ai_quiz`, `ai_resources` to report template
- [ ] Update UploadKnowledgeDocument to include guidance sections
- [ ] Test with 1-2 sample reports

### Phase 2: What-If Simulation (2-3 sprints)
- [ ] Implement `RunWhatIfSimulation` tool
- [ ] Support parameter overrides (lookback, SKU, Spot rules)
- [ ] Side-by-side comparison output

### Phase 3: Interactive Report UI (3-4 sprints)
- [ ] Build HTML/Markdown dashboard for persisted reports
- [ ] Embed expandable guidance sections
- [ ] Add Q&A chat (optional; depends on platform support)

### Phase 4: Multi-Model Support (4-5 sprints)
- [ ] Abstract optimization backend (currently Azure Advisor)
- [ ] Support BYO model configuration
- [ ] Add usage metering & audit logging

---

## 6. Key Takeaways

1. **Automation + Guidance**: Skillable pairs automation (scripts, vision) with learning (chat, guidance). Apply this: auto-generate remediation scripts + provide interactive guidance.

2. **Structured Content**: Use tags (`ai_teach`, etc.) to keep authoring modular and runtime flexible. Enables multiple output modes (concise, detailed, interactive).

3. **Extensibility**: Skillable's BYO model approach shows value in flexibility. Your SRE engine should support multiple optimization backends, not just Azure Advisor.

4. **Learner/SRE Engagement**: Skillable emphasizes real-time support (chat, Q&A). Embed guidance directly in your reports so SREs can self-serve.

5. **Validation**: Skillable's AI Vision (visual checks) complements your API-based validation. Consider adding screenshot audit trails for configuration changes.

---

## 7. Next Steps

1. **Assess feasibility**: Which enhancements fit your current platform constraints?
2. **Pilot one enhancement**: Start with metadata tags (lowest effort, high value).
3. **Iterate**: Gather SRE feedback; refine guidance templates.
4. **Scale**: Roll out to other subagents (storage, network, governance).

---

## References
- [Skillable AI Documentation](https://docs.skillable.com/docs/skillable-ai)
- Current: [Compute-Optimization-Specialist subagent.yaml](../subagents/compute-optimization/subagent.yaml)
- Related: [FitScore-Methodology.md](../knowledge-base/FitScore-Methodology.md), [SKU-Constraint-Rules.md](../knowledge-base/SKU-Constraint-Rules.md)
