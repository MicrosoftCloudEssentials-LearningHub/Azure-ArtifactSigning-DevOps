# Azure Artifact Signing (Azure DevOps + Terraform)

This repo is a minimal, demo-friendly setup for:
- Provisioning Azure Artifact Signing (Trusted Signing) resources with Terraform.
- Building a small Windows .NET executable.
- Signing it in Azure DevOps using **SignTool + Artifact Signing dlib** (private key stays in Microsoft-managed HSMs).

## What Terraform creates

- Resource group
- Artifact Signing account (`Microsoft.CodeSigning/codeSigningAccounts`)
- (Optional, Terraform-deployed) Certificate profile (`.../certificateProfiles`) once you provide an **Identity validation Id**
- (Optional, Terraform-deployed) Microsoft Entra app registration + service principal for an Azure DevOps **Workload Identity Federation** service connection
- (Optional, Terraform-deployed) Azure DevOps resources (when `ado_enabled = true`):
   - Project
   - Git repo
   - YAML pipeline
   - AzureRM service connection (Workload Identity Federation)
   - Pipeline authorizations for the service connection + variable group
- (Optional, Terraform-deployed) RBAC assignment: `Artifact Signing Certificate Profile Signer` at the certificate profile scope

Notes:
- **Identity validation** itself is **portal-only** (service requirement). Terraform can’t complete that workflow; you paste the resulting `identity_validation_id` into `terraform.tfvars`.
- If Terraform creates the Azure DevOps service connection (`ado_enabled = true`), it can also read the generated WIF **Issuer** and **Subject** and create the Entra **federated credential** automatically (no copy/paste).

## Prereqs

- Azure CLI installed and logged in (`az login`)
- Terraform installed
- Permission to register resource providers + create resources in your subscription

One-time provider registration (per subscription):

```pwsh
az provider register --namespace Microsoft.CodeSigning
```

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

3) In Azure portal, open the Artifact Signing account and complete **Identity validation** (portal-only).

4) Copy the **Identity validation Id** from the portal and add it to `terraform-infrastructure/terraform.tfvars`:

```hcl
identity_validation_id = "00000000-0000-0000-0000-000000000000"
certificate_profile_name = "demo-code-signing"
certificate_profile_type = "PublicTrustTest"
```

5) Apply again to create the certificate profile:

```pwsh
cd terraform-infrastructure
terraform validate
terraform apply -auto-approve
```

## Azure DevOps (Terraform-managed)

This repo can also create the Azure DevOps project/repo/pipeline/service-connection using the Terraform `azuredevops` provider.

1) Create a PAT in Azure DevOps with permissions to manage projects/repos/pipelines/service connections.

2) Set env vars (PowerShell):

```pwsh
$env:AZDO_ORG_SERVICE_URL = "https://dev.azure.com/<your-org>"
$env:AZDO_PERSONAL_ACCESS_TOKEN = "<your-pat>"
```

3) In `terraform-infrastructure/terraform.tfvars`, set:

```hcl
ado_enabled = true
ado_org_service_url = "https://dev.azure.com/<your-org>"
```

4) Apply. Terraform will:
- create the Azure DevOps project + repo + YAML pipeline
- create the AzureRM service connection using Workload Identity Federation (WIF)
- read the generated WIF Issuer/Subject and create the Entra federated credential

Notes:
- The `WorkloadIdentityFederation` auth scheme requires your org feature to be enabled. If your org can’t use it yet, set `ado_service_endpoint_authentication_scheme = "ServicePrincipal"` and also set `TF_VAR_ado_service_principal_client_secret` for the service principal secret.
- Terraform creates an empty repo. You still need to push this repo’s code into the Azure DevOps repo (Terraform will output the clone URL).

## Pipeline

- [azure-pipelines.yml](azure-pipelines.yml) builds `SigningDemo.exe`, installs the required signing components via NuGet extraction, then signs using the official SignTool + `/dlib` flow.
- Configure pipeline variables:
  - `artifactSigningEndpoint` (Terraform output `artifact_signing_endpoint`)
  - `artifactSigningAccountName` (Terraform output `artifact_signing_account_name`)
  - `artifactSigningCertificateProfileName` (your profile name)
  - Service connection name in YAML: update `azureSubscription` if you didn't name it `sc-artifact-signing`.

### Optional: use Azure Key Vault for pipeline variables

If you enable Key Vault (`keyvault_enabled=true`) Terraform will:
- create an RBAC-enabled Key Vault
- grant your current identity **Key Vault Secrets Officer** (so you can set secrets)
- grant the Azure DevOps service principal **Key Vault Secrets User** (so the pipeline can read secrets)

Then create secrets in Key Vault with these names:
- `artifactSigningEndpoint`
- `artifactSigningAccountName`
- `artifactSigningCertificateProfileName`

The pipeline will automatically load them (it runs `AzureKeyVault@2` when `keyVaultName` is non-empty).

If signing fails with 403, validate:
- Endpoint matches region
- Service connection identity has `Artifact Signing Certificate Profile Signer` at the certificate profile scope

## Azure Portal link

After `terraform apply`, open the resource group:
https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups
