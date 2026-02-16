# Contributing Guide

Thank you for your interest in contributing to the SRE Agent Optimization Engine Subagents project. This guide explains how to add new subagents, knowledge base documents, and tests.

---

## Attribution

> **Important:** This project is derived from and inspired by the [Azure Optimization Engine (AOE)](https://github.com/helderpinto/AzureOptimizationEngine) by **Hélder Pinto**. Any logic, methodology, or scoring approach that originates from AOE must be credited appropriately.

### Attribution Requirements

When contributing code or documentation that derives from AOE:

1. Include a comment or note referencing the AOE source
2. Credit Hélder Pinto by name in documentation
3. Link to the original AOE repository where applicable
4. Do not remove existing attribution notices

Example attribution:

```markdown
> Derived from Azure Optimization Engine (AOE) by Hélder Pinto.
> Original: https://github.com/helderpinto/AzureOptimizationEngine
```

---

## How to Add a New Subagent

### 1. Create the Directory Structure

```bash
mkdir -p subagents/<subagent-name>
```

### 2. Create the Agent Configuration

Create `subagents/<subagent-name>/subagent.yaml`:

```yaml
name: "<subagent-name>"
description: "<What this subagent does>"
version: "1.0.0"

tools:
  - azure_resource_graph
  - azure_advisor
  - azure_monitor

knowledge_base:
  - FitScore-Methodology.md
  - Threshold-Defaults.md
  - SKU-Constraint-Rules.md
  # Add subagent-specific knowledge base documents

instructions: |
  You are a specialist subagent for <domain> optimization.
  Your responsibilities:
  1. <Primary responsibility>
  2. <Secondary responsibility>
  3. <Additional responsibilities>
  
  Follow the FitScore methodology and output format defined in the knowledge base.
```

### 3. Create the Schedule Configuration

Create `subagents/<subagent-name>/schedule.yaml`:

```yaml
schedule:
  cron: "0 6 * * *"       # Adjust for the appropriate frequency
  timezone: "UTC"
  enabled: true
```

### 4. Create a README

Create `subagents/<subagent-name>/README.md` describing:

- What the subagent does
- Which Azure resource types it covers
- Which AOE runbooks it replaces (if any)
- Knowledge base dependencies
- Example output

### 5. Add Knowledge Base Documents (if needed)

If the subagent requires domain-specific knowledge:

1. Create the document in `knowledge-base/`
2. Follow the naming convention: `<Topic>-<Subtopic>.md`
3. Use declarative language (the LLM interprets these as instructions)
4. Reference existing documents rather than duplicating content

### 6. Register with the Orchestrator

Update `subagents/orchestrator/subagent.yaml` to include the new subagent:

```yaml
subagents:
  - compute-optimization
  - storage-optimization
  - network-optimization
  - paas-optimization
  - governance-compliance
  - <your-new-subagent>       # Add here
```

---

## How to Add Knowledge Base Documents

### Guidelines

1. **One topic per document** — keep documents focused
2. **Declarative language** — describe *what* to do, not *how* to code
3. **Include examples** — provide sample KQL queries, expected outputs, and threshold values
4. **Reference, don't duplicate** — link to other knowledge base docs
5. **Version awareness** — note if the document depends on specific Azure API versions

### Template

```markdown
# <Document Title>

## Purpose
<What this document provides to the subagent>

## Rules / Methodology
<The core logic, rules, or methodology>

## Thresholds / Defaults
| Parameter | Default | Description |
|---|---|---|
| ... | ... | ... |

## Queries
<KQL or other query examples>

## Output Format
<Expected output format for recommendations using this logic>

## References
- [Related Document](Related-Document.md)
- [Azure Documentation](https://learn.microsoft.com/...)
```

### Naming Convention

- Use PascalCase with hyphens: `FitScore-Methodology.md`, `SKU-Constraint-Rules.md`
- Be descriptive: `VM-Deallocated-Detection.md` not `dealloc.md`

---

## Testing Requirements

### All Contributions Must Include

1. **Test scenarios** — at least one test scenario in `tests/scenarios/` for new detection logic
2. **FitScore test cases** — if the change affects FitScore calculation, add cases to `tests/fitscore-test-cases.md`
3. **Validation steps** — document how to verify the change works correctly

### Test Scenario Template

Create a file in `tests/scenarios/<scenario-name>.md`:

```markdown
# Test Scenario: <Scenario Name>

## Objective
<What this test validates>

## Setup
<Azure CLI commands to create test resources>

## Expected Results
<What the subagent should detect and recommend>

## Verification Steps
<How to confirm the test passes>

## Cleanup
<Azure CLI commands to delete test resources>
```

### Running Tests

```bash
# Set up test subscription (if not already done)
# Follow tests/test-subscription-setup.md

# Run the specific subagent against the test subscription
# az sre-agent subagent run \
#   --resource-group $AGENT_RG \
#   --agent-name $AGENT_NAME \
#   --subagent <subagent-name> \
#   --scope "/subscriptions/<test-subscription-id>"

# Compare output against expected results in the test scenario
```

---

## Pull Request Process

### Before Submitting

1. [ ] All new/modified knowledge base documents follow the template
2. [ ] Test scenarios are included for new detection logic
3. [ ] FitScore test cases updated (if applicable)
4. [ ] YAML configurations are valid (no syntax errors)
5. [ ] Attribution is included for any AOE-derived logic
6. [ ] README updated (if adding a new subagent)

### PR Description Template

```markdown
## Summary
<Brief description of the change>

## Type of Change
- [ ] New subagent
- [ ] New knowledge base document
- [ ] Modified existing logic
- [ ] Bug fix
- [ ] Documentation update

## AOE Derivation
- [ ] This change derives from AOE logic (attribution included)
- [ ] This change is original (not derived from AOE)

## Testing
- [ ] Test scenario added/updated
- [ ] FitScore test cases added/updated
- [ ] Manually tested against test subscription
- [ ] Compared results with AOE (if applicable)

## Checklist
- [ ] Knowledge base follows template
- [ ] YAML is valid
- [ ] Attribution included
- [ ] README updated
```

### Review Process

1. Submit PR with completed description template
2. Automated checks: YAML validation, markdown lint
3. Peer review: at least one approval required
4. Maintainer review: for knowledge base changes affecting FitScore or thresholds
5. Merge to main branch
6. Re-deploy affected subagents (follow [deployment-guide.md](deployment-guide.md))

---

## Code of Conduct

This project follows the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

- Be respectful and constructive in all interactions
- Welcome newcomers and help them get started
- Focus on the technical merit of contributions
- Credit original authors for derived work

For questions or concerns, contact the project maintainers.

---

## Getting Help

| Need | Where |
|---|---|
| Architecture questions | See [docs/architecture.md](architecture.md) |
| Configuration help | See [docs/configuration.md](configuration.md) |
| Deployment issues | See [docs/deployment-guide.md](deployment-guide.md) |
| AOE comparison | See [docs/aoe-comparison.md](aoe-comparison.md) |
| Test setup | See [tests/test-subscription-setup.md](../tests/test-subscription-setup.md) |
