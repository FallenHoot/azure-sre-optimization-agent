# Changelog

All notable changes to the Azure Optimization Subagents project will be documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Bicep IaC templates** (`infra/`)
  - Subscription-scoped deployment (Agent + MI + LA + App Insights + RBAC)
  - Multi-region support (swedencentral, eastus2, australiaeast, uksouth)
  - User-Assigned Managed Identity (fixes BuildingKnowledgeGraph stuck state)
  - Target resource group RBAC module
  - Example parameter files for multi-RG scenarios

- **Demo environment** (`infra/demo/`)
  - AVM-based Bicep templates for test workloads
  - 3 VMs (oversized, idle, dev/test), 2 orphan disks, 2 storage accounts
  - Auto-shutdown at 7 PM CET to control costs
  - Deploy script (`deploy-demo.ps1`)

- **Deployment automation**
  - `deploy.ps1` — Full Bicep deployment with RBAC + knowledge graph wait
  - `deploy-subagents.ps1` — Subagent creation via REST API with portal-paste fallback

- **Enhanced subagent instructions**
  - Disk tier decision matrix (Premium SSD v1/v2, Standard SSD, HDD)
  - SKU generation intelligence (v4 → v5/v6 migration paths)
  - Spot VM eligibility analysis
  - Live Azure API queries replace static data tables
  - 3-tier data hierarchy: Live APIs > MS Learn docs > Static KB files

### Changed

- **Region standardization** — All scripts, docs, and test data now default to `swedencentral`
- **Deployment docs consolidated** — `docs/deployment-guide.md` now routes to Bicep guide or portal guide
- **README updated** — Added repo structure, contributing section, current phase status
- **Test scenarios** updated to reference demo environment resources

### Removed

- `subagent.yaml.legacy` — Superseded by 6 individual subagent YAML files (archived to `docs/archive/`)
- `portal-paste/` directory — Superseded by `deploy-subagents.ps1` dynamic generation
- `AOE-SRE-Agent-Analysis.md` — Archived (superseded by `docs/aoe-comparison.md`)
- `AOE-SRE-Agent-PoC-README.md` — Archived (superseded by `README.md` + docs/)

### Upcoming

- **CLI for subagent management** — There are signs that a native Azure CLI experience for creating and managing SRE Agent subagents may be on the horizon. When available, this would significantly simplify deployment by replacing the current REST API / portal-paste workflow in `deploy-subagents.ps1`. Watch this space.

### Fixed

- Hardcoded `eastus` / `eastus2` region references across 6 files
- `availabilityZone` → `zone` property name in AVM VM module
- Hallucinated tools removed from subagent instructions (score 62→82)
- FitScore dead-end loop (chatty behavior fix)

---

## [0.1.0] — Initial PoC

### Added

- **Compute Optimization Specialist** subagent (Phase 1 PoC)
  - VM rightsizing with FitScore validation (ported from AOE)
  - Deallocated VM detection (30+ days)
  - Stopped-not-deallocated VM detection (Critical)
  - High availability gap detection
  - Alternative SKU search (new — beyond AOE)
  - Weekly scheduled scan (Monday 6:00 AM UTC)

- **Storage Optimization Specialist** subagent stub (Phase 2)
  - Unattached disk detection
  - Over-provisioned disk tier detection
  - Storage account configuration analysis

- **Network Optimization Specialist** subagent stub (Phase 2)
  - Empty load balancer detection
  - Unused Application Gateway detection
  - Orphaned network resource detection

- **PaaS Optimization Specialist** subagent stub (Phase 2)
  - App Service Plan rightsizing
  - SQL Database tier optimization

- **Governance & Compliance Specialist** subagent stub (Phase 2)
  - Expiring credential detection
  - Outdated API version detection
  - Non-cost Advisor recommendations

- **Orchestrator** subagent stub (Phase 2)
  - Cross-domain report aggregation

- **Knowledge Base** (10 documents)
  - FitScore-Methodology.md — Core algorithm from AOE
  - SKU-Constraint-Rules.md — Hardware constraint validation
  - Threshold-Defaults.md — Default metric thresholds
  - Recommendation-Format.md — Output schema
  - Savings-Estimation.md — Pricing calculation methods
  - Severity-Classification.md — Alert severity rules
  - Resource-Graph-Queries.md — Pre-built ARG queries
  - Metric-Collection-Guide.md — Azure Monitor patterns
  - Escalation-Criteria.md — Ticket/alert escalation rules
  - Workload-Patterns.md — AI-powered pattern detection (new)

- **Deployment scripts**
  - deploy-sre-agent.sh — Provisioning guide
  - setup-rbac.sh — RBAC configuration
  - validate-access.sh — API access verification

- **Test framework**
  - FitScore test cases (10 scenarios)
  - Integration test scenarios (5 scenarios)
  - AOE comparison test framework

- **Documentation**
  - Architecture decisions
  - AOE feature comparison
  - Deployment guide
  - Configuration guide
  - Contributing guide
