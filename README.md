# Demo: Azure Artifact Signing (GitHub Actions + Terraform)

Costa Rica

[![GitHub](https://img.shields.io/badge/--181717?logo=github&logoColor=ffffff)](https://github.com/)
[brown9804](https://github.com/brown9804)

Last updated: 2026-02-19

----------

`In GitHub Actions, code signing is an automated workflow step that runs after build, using a cloud‑hosted certificate where the private key never leaves Azure`. The workflow then uses SignTool + the Artifact Signing dlib to call the service endpoint associated with those resources.

> - “Trusted Signing” = service branding/experience
> - “Microsoft.CodeSigning/*” = the deployable Azure resources you manage with Terraform/ARM.

<details>
<summary><b>List of References </b> (Click to expand)</summary>

- [What is Artifact Signing?](https://learn.microsoft.com/en-us/azure/artifact-signing/overview)
- [Artifact Signing](https://azure.microsoft.com/en-us/products/artifact-signing?msockid=38ec3806873362243e122ce086486339)
- [Artifact Signing pricing](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/?msockid=38ec3806873362243e122ce086486339)
- [Quickstart: Set up Artifact Signing](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart?tabs=registerrp-portal%2Caccount-portal%2Corgvalidation%2Ccertificateprofile-portal%2Cdeleteresources-portal)
- [Set up signing integrations to use Artifact Signing](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations)
- [Microsoft Included CA Certificate List](https://ccadb.my.salesforce-sites.com/microsoft/IncludedCACertificateReportForMSFT)
- [Artifact Signing trust models](https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/artifact-signing/concept-trust-models.md)

</details>

> This repo is a minimal, demo-friendly setup for:
> - Provisioning Azure Artifact Signing (Trusted Signing) resources with Terraform.
> - Building a small Windows .NET executable.
> - Signing it in GitHub Actions using **SignTool + Artifact Signing dlib** (private key stays in Microsoft-managed HSMs).

   <img width="1523" height="743" alt="image" src="https://github.com/user-attachments/assets/5617dfde-d84b-4dd9-904f-7669b4de9374" />

## Prereqs

- Azure CLI installed and logged in (`az login`)
- Terraform installed
- Permission to register resource providers + create resources in your subscription. One-time provider registration (per subscription):

   ```pwsh
   az provider register --namespace Microsoft.CodeSigning
   ```
   
   <img width="772" height="559" alt="arch_Azure-Artifact-Signing_Demo drawio" src="https://github.com/user-attachments/assets/6a8a9f88-7a2b-4f26-8564-7cf39c5f47ff" />

## What Terraform creates

- Resource group
- Artifact Signing account (`Microsoft.CodeSigning/codeSigningAccounts`)
- Key Vault (RBAC-enabled) for pipeline variables/secrets (created by default)

  <img width="650" alt="image" src="https://github.com/user-attachments/assets/c8bd7550-d77f-411d-bed8-8e016fe7d1e9" />

> [!NOTE]
> identity validation + Certificate profile are created in the Azure Portal (service requirement).

<img width="650" alt="image" src="https://github.com/user-attachments/assets/16ef1341-6230-4908-bb32-af17c7af9223" />

Optional advanced paths:
- Terraform can create the certificate profile if you set `identity_validation_id` and re-run `terraform apply`.
- The GitHub Actions workflow can create it if you opt in via `AUTO_CREATE_CERT_PROFILE: 'true'` in the workflow (requires broader RBAC such as RG `Contributor`).

When `github_enabled = true`, Terraform also creates:
- Entra app registration + service principal for GitHub Actions (OIDC)
- Federated identity credential for `token.actions.githubusercontent.com`

<img width="451" height="622" alt="image" src="https://github.com/user-attachments/assets/1306d110-be8f-49a8-96dc-c0354a2a6404" />

From [What is Artifact Signing?](https://learn.microsoft.com/en-us/azure/artifact-signing/overview)

> [!NOTE]
> - **Identity validation** itself is **portal-only** (service requirement). Terraform can’t complete that workflow.
> - The **Identity validation Id** is not exposed via the Azure management API for the code signing account, so Terraform cannot “wait and fetch” it automatically.
> - Identity validation + certificate profile creation can be done entirely in the portal.
> - If you want Terraform (or the workflow) to create the certificate profile, you must copy the Identity validation Id from the portal.

## Deploy with Terraform

> Terraform files live in `terraform-infrastructure/`.

1) Edit `terraform-infrastructure/terraform.tfvars` and set a globally-unique account name. By default (`github_autodetect = true`), Terraform will auto-detect `github_owner/github_repo` during `terraform apply` (from GitHub Actions env vars if present, otherwise from your local git `origin`). `github_ref` defaults to `refs/heads/main` unless you set it explicitly. If this repo is not a git clone (for example, you downloaded a zip) or `origin` is not set to GitHub, autodetect can’t determine the values.

> [!IMPORTANT]
> If you're using GitHub Actions, prefer the fully automated bootstrap path below (it configures GitHub OIDC + secrets and runs Terraform for you):
   ```pwsh
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-github-actions.ps1
   ```
> Not using the bootstrap script? See the internal runbook: [_docs/README.md](_docs/README.md).

2) Run Terraform:

```pwsh
cd terraform-infrastructure
terraform init
terraform apply -auto-approve
```

<details>
<summary><b>What this first `terraform apply` does: </b> (Click to expand)</summary>

- Creates the resource group, Artifact Signing account, and Key Vault.
- Populates Key Vault secrets for the workflow (`artifactSigningEndpoint`, `artifactSigningAccountName`, `artifactSigningCertificateProfileName`).
- If `github_enabled = true`: creates the GitHub OIDC Entra app/service principal + federated identity credential, and assigns RBAC so the workflow can read Key Vault secrets and sign.

</details>

> [!IMPORTANT]
> What it cannot do: Complete Artifact Signing **identity validation** (this is portal-only).

Identity validation (portal-only). In [Azure portal](https://portal.azure.com/):
- Open the Artifact Signing account and complete **Identity validation**.

     <img width="650" height="811" alt="image" src="https://github.com/user-attachments/assets/e5a6c034-744b-4a9d-9981-36fd5b30d4a2" />
   
  https://github.com/user-attachments/assets/15359d56-9d15-4393-8db4-19971cb088a6

- Create the **certificate profile** (use the same name as `certificate_profile_name`).

https://github.com/user-attachments/assets/d42cd730-2f6c-4349-817a-9673b2d999d4

Optional (Terraform-managed certificate profile):
- Copy the **Identity validation Id** (GUID) from the portal.
- Paste it into `identity_validation_id` in `terraform-infrastructure/terraform.tfvars`.
- Run `terraform apply` again.

> [!TIP]
> Goal: You can now, push/merge to `main` (or run the workflow via `workflow_dispatch`). The [GitHub Actions workflow](.github/workflows/artifact-signing.yml) will build + sign the binaries.

## Azure Key Vault for workflow variables

> Terraform creates a Key Vault by default and wires RBAC so the workflow can read signing inputs.

| Principal | Role assigned | Why it exists |
| --- | --- | --- |
| Your current identity (the identity running `terraform apply`) | `Key Vault Secrets Officer` | Can set secrets during provisioning |
| GitHub Actions service principal | `Key Vault Secrets User` | Can read secrets at workflow runtime |

> [!NOTE]
> - This Key Vault is **RBAC-enabled** (`rbac_authorization_enabled = true`). You will see access under **Key Vault → Access control (IAM)** (not under “Access policies”).
> - The GitHub Actions workflow reads them from Key Vault at runtime using the Azure CLI.

Least privilege options:

| Setting / choice | Effect |
| --- | --- |
| `keyvault_populate_secrets = false` | Terraform will not write secrets into Key Vault (you can manage secrets yourself and/or set pipeline variables another way). |
| `keyvault_grant_keys_access_to_current = true` | Grants your current identity `Key Vault Crypto User` (lets you view **Keys** in the portal). |
| `keyvault_grant_certificates_access_to_current = true` | Grants your current identity `Key Vault Certificates User` (lets you view **Certificates** in the portal). |
| `keyvault_grant_administrator_to_current = true` | Simplest “make the portal work” option (broad permissions): grants your current identity `Key Vault Administrator`. |

Terraform also populates these Key Vault secrets during `terraform apply`:

| Secret name | Notes |
| --- | --- |
| `artifactSigningEndpoint` | Service endpoint used by the workflow |
| `artifactSigningAccountName` | Artifact Signing account name |
| `artifactSigningCertificateProfileName` | Certificate profile name |
| `artifactSigningIdentityValidationId` | Optional. Only needed if Terraform or the workflow will create the certificate profile. |

If signing fails with 403, validate:

| Check | Expected |
| --- | --- |
| Endpoint matches region | `artifactSigningEndpoint` points to the correct region |
| Role at certificate profile scope | GitHub Actions identity has `Artifact Signing Certificate Profile Signer` at the certificate profile scope |

## GitHub Actions

This repo includes a GitHub Actions workflow that performs the signing flow:
- build/publish unsigned exe
- load signing inputs from Key Vault
- sign + verify + upload artifact

Workflow file:
- [.github/workflows/artifact-signing.yml](.github/workflows/artifact-signing.yml)

### GitHub OIDC

> In this repo, OIDC + GitHub secrets are configured automatically by the bootstrap step in **Deploy with Terraform**.

Why this exists:
- GitHub Actions must authenticate to Azure to (1) read signing inputs from Key Vault and (2) call the Artifact Signing service.
- OIDC lets GitHub obtain an Azure token **without** storing an Azure client secret in GitHub.

> [!NOTE]
> Manual (service requirement): Complete the **Identity validation** step in the Azure Portal when prompted.

<!-- START BADGE -->
<div align="center">
  <img src="https://img.shields.io/badge/Total%20views-1280-limegreen" alt="Total views">
  <p>Refresh Date: 2026-02-19</p>
</div>
<!-- END BADGE -->
