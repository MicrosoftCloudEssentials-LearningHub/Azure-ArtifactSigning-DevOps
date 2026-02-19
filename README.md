# Demo: Azure Artifact Signing (GitHub Actions/ADO + Terraform)

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

## What Terraform creates

- Resource group
- Artifact Signing account (`Microsoft.CodeSigning/codeSigningAccounts`)
- Key Vault (RBAC-enabled) for pipeline variables/secrets (created by default)
- Certificate profile (`.../certificateProfiles`)
  - Preferred: created by the GitHub Actions workflow after you set the Key Vault secret `artifactSigningIdentityValidationId` (no second `terraform apply`)
  - Optional: created by Terraform if you set `identity_validation_id` and re-apply

When `github_enabled = true`, Terraform also creates:
- Entra app registration + service principal for GitHub Actions (OIDC)
- Federated identity credential for `token.actions.githubusercontent.com`

<img width="451" height="622" alt="image" src="https://github.com/user-attachments/assets/1306d110-be8f-49a8-96dc-c0354a2a6404" />

From [What is Artifact Signing?](https://learn.microsoft.com/en-us/azure/artifact-signing/overview)

> [!NOTE]
> - **Identity validation** itself is **portal-only** (service requirement). Terraform can’t complete that workflow.
> - After you complete it, set Key Vault secret `artifactSigningIdentityValidationId` and the GitHub Actions workflow will create the certificate profile automatically.

## Deploy with Terraform

Terraform files live in `terraform-infrastructure/`.

1) Edit `terraform-infrastructure/terraform.tfvars` and set a globally-unique account name.

2) Run Terraform:

```pwsh
cd terraform-infrastructure
terraform init
terraform validate
terraform apply -auto-approve
```

3) Artifact Signing **identity verification / identity validation** (portal-only):

- In Azure portal, open the Artifact Signing account and complete **Identity validation**.
- This is required by the service and cannot be automated by Terraform.
- If the portal says you need **Artifact Signing Identity Verifier**, re-run Terraform (it assigns this role to the identity running `terraform apply` by default) and wait a few minutes for RBAC to propagate.

4) Copy the **Identity validation Id** from the portal and set it in Key Vault:

```pwsh
$kvName = terraform -chdir=terraform-infrastructure output -raw keyvault_name
az keyvault secret set --vault-name $kvName --name artifactSigningIdentityValidationId --value "00000000-0000-0000-0000-000000000000"
```

5) Run the GitHub Actions workflow. It will create the certificate profile if it doesn’t exist yet, then sign the binaries.

Optional: If you prefer Terraform to manage the certificate profile instead, set `identity_validation_id` in `terraform-infrastructure/terraform.tfvars` and run `terraform apply` again.

## Azure Key Vault for workflow variables

Terraform creates a Key Vault by default and wires RBAC so:
- your current identity (the identity running `terraform apply`) can set secrets (`Key Vault Secrets Officer`)
- the GitHub Actions service principal can read secrets (`Key Vault Secrets User`)

> This Key Vault is **RBAC-enabled** (`rbac_authorization_enabled = true`). You will see access under **Key Vault → Access control (IAM)** (not under “Access policies”).

Least privilege options:
- Set `keyvault_populate_secrets = false` if you do not want Terraform to write secrets into Key Vault (you can manage secrets yourself and/or set pipeline variables another way).
- If you want to view **Keys** and/or **Certificates** in the Azure portal, opt in to RBAC for your current identity:
  - `keyvault_grant_keys_access_to_current = true` (assigns `Key Vault Crypto User`)
  - `keyvault_grant_certificates_access_to_current = true` (assigns `Key Vault Certificates User`)
  - Or, if you want the simplest “make the portal work” option (broad permissions):
    - `keyvault_grant_administrator_to_current = true` (assigns `Key Vault Administrator`)

Terraform also populates these Key Vault secrets during `terraform apply`:
- `artifactSigningEndpoint`
- `artifactSigningAccountName`
- `artifactSigningCertificateProfileName`
- `artifactSigningIdentityValidationId` (placeholder until you set it after portal validation)

The GitHub Actions workflow reads them from Key Vault at runtime using the Azure CLI.

If signing fails with 403, validate:
- Endpoint matches region
- GitHub Actions identity has `Artifact Signing Certificate Profile Signer` at the certificate profile scope

## GitHub Actions (recommended)

This repo includes a GitHub Actions workflow that performs the end-to-end signing flow:
- build/publish unsigned exe
- load signing inputs from Key Vault
- create the certificate profile if missing (after you complete portal identity validation)
- sign + verify + upload artifact

Workflow file:
- [.github/workflows/artifact-signing.yml](.github/workflows/artifact-signing.yml)

### Enable GitHub OIDC (Terraform)

1) In [terraform-infrastructure/terraform.tfvars](terraform-infrastructure/terraform.tfvars), set:
- `github_enabled = true`
- `github_owner = "<your-owner>"`
- `github_repo = "<your-repo>"`
- `github_ref = "refs/heads/main"` (or your default branch)

2) Run:

```pwsh
cd terraform-infrastructure
terraform apply -auto-approve
```

Terraform outputs the Entra app client id for GitHub:
- `github_app_client_id`

### Configure GitHub repo secrets

In GitHub → Settings → Secrets and variables → Actions, set these **Secrets**:

- `AZURE_CLIENT_ID` = Terraform output `github_app_client_id`
- `AZURE_TENANT_ID` = your Entra tenant id
- `AZURE_SUBSCRIPTION_ID` = your Azure subscription id
- `KEYVAULT_NAME` = Terraform output `keyvault_name`
- `ARTIFACT_SIGNING_RESOURCE_GROUP` = Terraform output `resource_group_name`

Then push to `main` (or run the workflow manually via `workflow_dispatch`).

Notes:
- The workflow uses OIDC, so there is no Azure client secret.
- The GitHub Actions identity must have RBAC to read Key Vault secrets (`Key Vault Secrets User`) and to sign (`Artifact Signing Certificate Profile Signer`).
- If you want the workflow to auto-create the certificate profile, you typically also need RG `Contributor` for that identity (`assign_contributor_role_to_github_sp = true`).

## Azure Portal link

After `terraform apply`, open the resource group:
https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups

<!-- START BADGE -->
<div align="center">
  <img src="https://img.shields.io/badge/Total%20views-1280-limegreen" alt="Total views">
  <p>Refresh Date: 2026-02-19</p>
</div>
<!-- END BADGE -->
