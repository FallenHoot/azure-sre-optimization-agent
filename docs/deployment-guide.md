# Deployment Guide

Choose the deployment path that matches your scenario:

---

## Option 1 — Bicep + PowerShell (Recommended)

Automated deployment using Infrastructure as Code. Creates the SRE Agent, Managed Identity, Log Analytics, Application Insights, and RBAC in a single command.

```powershell
.\scripts\deploy.ps1
```

📖 Full guide: [infra/README.md](../infra/README.md)

---

## Option 2 — Azure Portal (Step-by-Step)

Manual deployment with portal screenshots and field-by-field mapping from YAML configs. Best for first-time setup or environments where CLI access is restricted.

📖 Full guide: [DEPLOY-TO-SRE-AGENT.md](DEPLOY-TO-SRE-AGENT.md)

---

## After Deployment

Once the agent is running:

1. **Upload Knowledge Base** — All 10 files from `knowledge-base/`
2. **Create Subagents** — Use `scripts/deploy-subagents.ps1` or follow the portal guide
3. **Configure Schedules** — Each subagent has a `schedule.yaml`
4. **Test** — Run playground prompts from the portal guide
5. **Customize** — See [configuration.md](configuration.md) for threshold overrides

## Related Docs

| Document | Purpose |
|----------|---------|
| [infra/README.md](../infra/README.md) | Bicep template details, parameters, troubleshooting |
| [DEPLOY-TO-SRE-AGENT.md](DEPLOY-TO-SRE-AGENT.md) | Portal walkthrough with field mapping |
| [configuration.md](configuration.md) | Threshold and behavior customization |
| [architecture.md](architecture.md) | System architecture and design decisions |
| [contributing.md](contributing.md) | How to contribute |
