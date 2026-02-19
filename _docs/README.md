# Internal runbook (maintainers)

Costa Rica

[![GitHub](https://img.shields.io/badge/--181717?logo=github&logoColor=ffffff)](https://github.com/)
[brown9804](https://github.com/brown9804)

Last updated: 2026-02-19

----------

This repo intentionally keeps the main [README.md](../README.md) focused on a minimal, demo-friendly UX.

The scripts below exist to make the setup idempotent and “one command” for end users, while still giving maintainers an escape hatch for non-interactive automation.

## Scripts overview

- `scripts/bootstrap-github-actions.ps1`
  - End-user entrypoint for GitHub Actions setup.
  - Handles GitHub OIDC config, Terraform apply, and `gh` secrets.

- `scripts/terraform-apply.ps1`
  - Backend wrapper for Terraform.
  - Provides a friendlier Terraform apply experience and optional helper flow for Terraform-managed certificate profile creation.

- `scripts/configure-github-oidc.ps1`
  - Persists `github_enabled/github_owner/github_repo/github_ref` into `terraform-infrastructure/terraform.tfvars`.
  - Useful if running from a zip/no `git origin`, or if you want deterministic tfvars.

## Typical flows

### End-user: GitHub Actions (preferred)

- Run:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-github-actions.ps1`

What it does:
- Writes GitHub OIDC settings into `terraform-infrastructure/terraform.tfvars`.
- Runs Terraform once to provision infra + RBAC.
- Sets GitHub Actions secrets via `gh`.

What remains manual (service requirement):
- In Azure Portal, complete Identity validation.
- In Azure Portal, create the certificate profile (use the same name as `certificate_profile_name`).

### Maintainer: Terraform wrapper only (interactive)

Use when you’re iterating on Terraform without touching GitHub secrets.

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\terraform-apply.ps1 -Interactive`

Behavior:
- Runs `terraform init`, `terraform validate`, `terraform apply`.
- If `identity_validation_id` is still empty, it explains the portal steps.
- If you paste an Identity validation Id (GUID), it persists it and re-applies (Terraform-managed certificate profile).

### Maintainer: Terraform wrapper only (non-interactive)

Use when you want a single apply, no prompts.

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\terraform-apply.ps1`

### Maintainer: Persist Identity validation Id (non-interactive)

Use when you already have the Id and want to persist it into `terraform.tfvars` without manually editing the file.

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\terraform-apply.ps1 -IdentityValidationId <GUID>`

Notes:
- Still requires the portal Identity validation to have been completed already.

### Maintainer: Bootstrap without guided identity flow

If you want bootstrap to run a single Terraform apply (no prompt), use:

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-github-actions.ps1 -TerraformApplyMode noninteractive`

## Why the portal step exists

Artifact Signing identity validation is a service requirement and is currently portal-driven. The Identity validation Id is not exposed via the management API for the signing account, so Terraform cannot “wait and fetch” it.

<!-- START BADGE -->
<div align="center">
  <img src="https://img.shields.io/badge/Total%20views-1280-limegreen" alt="Total views">
  <p>Refresh Date: 2026-02-19</p>
</div>
<!-- END BADGE -->
