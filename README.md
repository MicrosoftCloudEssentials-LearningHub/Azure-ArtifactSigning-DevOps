# Azure Artifact Signing (Azure DevOps + Terraform)

Costa Rica

[![GitHub](https://img.shields.io/badge/--181717?logo=github&logoColor=ffffff)](https://github.com/)
[brown9804](https://github.com/brown9804)

Last updated: 2026-02-19

----------

`In Azure DevOps, code signing is an automated pipeline step that runs after build, using a cloud‑hosted certificate where the private key never leaves Azure`. The pipeline then uses SignTool + the Artifact Signing dlib to call the service endpoint associated with those resources.

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
> - Signing it in Azure DevOps using **SignTool + Artifact Signing dlib** (private key stays in Microsoft-managed HSMs).

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
  - Preferred: created by the Azure DevOps pipeline after you set the Key Vault secret `artifactSigningIdentityValidationId` (no second `terraform apply`)
  - Optional: created by Terraform if you set `identity_validation_id` and re-apply
- Optional Azure DevOps resources (when `ado_enabled = true`)
  - Entra app registration + service principal
  - Azure DevOps project/repo/pipeline/service connection + authorizations

<img width="451" height="622" alt="image" src="https://github.com/user-attachments/assets/1306d110-be8f-49a8-96dc-c0354a2a6404" />

From [What is Artifact Signing?](https://learn.microsoft.com/en-us/azure/artifact-signing/overview)

> [!NOTE]
> - **Identity validation** itself is **portal-only** (service requirement). Terraform can’t complete that workflow.
> - After you complete it, set Key Vault secret `artifactSigningIdentityValidationId` and the pipeline will create the certificate profile automatically.
> - If Terraform creates the Azure DevOps service connection (`ado_enabled = true`), it can read the generated WIF **Issuer/Subject** and create the Entra federated credential automatically.

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

5) Run the Azure DevOps pipeline. The `AzureCLI@2` step will create the certificate profile if it doesn’t exist yet, then sign the binaries.

Optional: If you prefer Terraform to manage the certificate profile instead, set `identity_validation_id` in `terraform-infrastructure/terraform.tfvars` and run `terraform apply` again.

## Azure DevOps (Terraform-managed)

This repo can also create the Azure DevOps project/repo/pipeline/service-connection using the Terraform `azuredevops` provider.

1) Create a PAT in Azure DevOps with permissions to manage projects/repos/pipelines/service connections.

2) Set env vars (PowerShell):

```pwsh
$env:AZDO_ORG_SERVICE_URL = "https://dev.azure.com/<your-org>"
$env:AZDO_PERSONAL_ACCESS_TOKEN = "<your-pat>"
```

3) Enable the Azure DevOps resources in Terraform.

Preferred: use the provided var-file:

```pwsh
cd terraform-infrastructure
terraform apply -auto-approve -var-file=terraform.tfvars -var-file=terraform.ado.tfvars
```

Alternative: set `ado_enabled = true` and `ado_org_service_url` in `terraform.tfvars`.

> If you prefer variables over env vars, you can also set `$env:TF_VAR_ado_org_service_url = "https://dev.azure.com/<your-org>"`.

4) Terraform will:
- create the Azure DevOps project + repo + YAML pipeline
- create the AzureRM service connection using Workload Identity Federation (WIF)
- read the generated WIF Issuer/Subject and create the Entra federated credential

Notes:
- Artifact Signing identity validation remains **portal-only** even when Azure DevOps is Terraform-managed. Treat it as part of the "Deploy with Terraform" flow above (once completed, store the Id in Key Vault and the pipeline can create the certificate profile automatically).
- The `WorkloadIdentityFederation` auth scheme requires your org feature to be enabled. If your org can’t use it yet, set `ado_service_endpoint_authentication_scheme = "ServicePrincipal"` and also set `TF_VAR_ado_service_principal_client_secret` for the service principal secret.
- Terraform creates an empty repo. You still need to push this repo’s code into the Azure DevOps repo (Terraform will output the clone URL).
- Least privilege: by default this repo does **not** grant RG `Contributor` to the Azure DevOps service principal. If you want the pipeline to auto-create the certificate profile, set `assign_contributor_role_to_ado_sp = true`.

## Pipeline

- [azure-pipelines.yml](azure-pipelines.yml) builds `SigningDemo.exe`, installs the required signing components via NuGet extraction, then signs using the official SignTool + `/dlib` flow.
- If `keyVaultName` is set, the pipeline loads signing values from Key Vault via `AzureKeyVault@2`.

Minimum pipeline variables (when not using the Terraform-managed variable group):
- `azureServiceConnection` (service connection name; default `sc-artifact-signing`)
- `keyVaultName` (Terraform output `keyvault_name`)
- `artifactSigningResourceGroupName` (Terraform `resource_group_name`)

Optional overrides (normally provided by Key Vault):
- `artifactSigningEndpoint`
- `artifactSigningAccountName`
- `artifactSigningCertificateProfileName`
- `artifactSigningIdentityValidationId` (only required until the profile exists)

Optional (only used when creating the certificate profile):
- `artifactSigningCertificateProfileType` (defaults to `PublicTrust` if unset)
- `adoServicePrincipalObjectId`

### Azure Key Vault for pipeline variables

Terraform creates a Key Vault by default and wires RBAC so:
- your current identity (the identity running `terraform apply`) can set secrets (`Key Vault Secrets Officer`)
- the Azure DevOps service principal can read secrets (`Key Vault Secrets User`)

> This Key Vault is **RBAC-enabled** (`rbac_authorization_enabled = true`). You will see access under **Key Vault → Access control (IAM)** (not under “Access policies”).

Least privilege options:
- Set `keyvault_populate_secrets = false` if you do not want Terraform to write secrets into Key Vault (you can manage secrets yourself and/or set pipeline variables another way).
- The pipeline does not attempt to self-assign RBAC by default (it only does if `pipeline_attempt_rbac_assignment = true`).
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

The pipeline automatically loads them (it runs `AzureKeyVault@2` when `keyVaultName` is non-empty).

If signing fails with 403, validate:
- Endpoint matches region
- Service connection identity has `Artifact Signing Certificate Profile Signer` at the certificate profile scope

## Azure Portal link

After `terraform apply`, open the resource group:
https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups

<!-- START BADGE -->
<div align="center">
  <img src="https://img.shields.io/badge/Total%20views-1280-limegreen" alt="Total views">
  <p>Refresh Date: 2026-02-19</p>
</div>
<!-- END BADGE -->
