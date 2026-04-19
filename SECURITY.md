# Security Policy

## Supported Versions

This project is currently maintained on the default branch only.

## Reporting a Vulnerability

Please do not open public issues for security vulnerabilities.

Report vulnerabilities privately by contacting the repository owner through GitHub Security Advisories (preferred) or another private channel.

When reporting, include:

- A clear description of the issue
- Steps to reproduce
- Potential impact
- Any suggested remediation

## Secret Handling Requirements

- Never commit credentials, API keys, tokens, certificates, or private keys.
- Use managed identities, environment variables, and secure secret stores such as Azure Key Vault.
- Rotate any credential immediately if accidental exposure is suspected.

## Repository Safety Notes

This repository is intended for reference and experimentation. Validate all generated remediation actions in a controlled environment before production use.
