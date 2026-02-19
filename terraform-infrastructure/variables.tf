variable "location" {
  type        = string
  description = "Azure region to deploy Artifact Signing resources (for example: eastus)."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name."
  default     = "rg-artifact-signing-demo"
}

variable "code_signing_account_name" {
  type        = string
  description = "Artifact Signing (Trusted Signing) account name. Must be globally unique, 3-24 characters."
}

variable "code_signing_sku" {
  type        = string
  description = "Artifact Signing account SKU."
  default     = "Basic"
  validation {
    condition     = contains(["Basic", "Premium"], var.code_signing_sku)
    error_message = "code_signing_sku must be one of: Basic, Premium."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources."
  default     = {}
}

variable "identity_validation_id" {
  type        = string
  description = "Identity validation ID from the Azure portal. Required to create a certificate profile. Set to null until identity validation is completed."
  default     = null
  nullable    = true
}

variable "certificate_profile_name" {
  type        = string
  description = "Certificate profile name (5-100 chars)."
  default     = "demo-code-signing"
}

variable "certificate_profile_type" {
  type        = string
  description = "Certificate profile type."
  default     = "PublicTrustTest"
  validation {
    condition     = contains(["PrivateTrust", "PrivateTrustCIPolicy", "PublicTrust", "PublicTrustTest", "VBSEnclave"], var.certificate_profile_type)
    error_message = "certificate_profile_type must be one of: PrivateTrust, PrivateTrustCIPolicy, PublicTrust, PublicTrustTest, VBSEnclave."
  }
}

variable "certificate_profile_include_street_address" {
  type        = bool
  description = "Whether to include STREET in the certificate subject name."
  default     = false
}

variable "certificate_profile_include_postal_code" {
  type        = bool
  description = "Whether to include PC in the certificate subject name."
  default     = false
}

variable "ado_app_display_name" {
  type        = string
  description = "Display name for the Entra app registration used by Azure DevOps service connection (Workload Identity Federation)."
  default     = "ado-artifact-signing-demo"
}

variable "ado_enabled" {
  type        = bool
  description = "If true, Terraform will manage Azure DevOps resources (project, repo, pipeline, and AzureRM service connection) using the azuredevops provider."
  default     = false
}

variable "ado_org_service_url" {
  type        = string
  description = "Azure DevOps organization URL, for example: https://dev.azure.com/your-org (also supported via AZDO_ORG_SERVICE_URL env var)."
  default     = null
  nullable    = true

  validation {
    condition     = var.ado_enabled == false || (var.ado_org_service_url != null && length(trimspace(var.ado_org_service_url)) > 0)
    error_message = "When ado_enabled=true you must set ado_org_service_url (or AZDO_ORG_SERVICE_URL)."
  }
}

variable "ado_project_name" {
  type        = string
  description = "Azure DevOps project name to create/manage."
  default     = "ArtifactSigningDemo"
}

variable "ado_project_description" {
  type        = string
  description = "Azure DevOps project description."
  default     = "Managed by Terraform"
}

variable "ado_project_visibility" {
  type        = string
  description = "Azure DevOps project visibility."
  default     = "private"
  validation {
    condition     = contains(["private", "public"], var.ado_project_visibility)
    error_message = "ado_project_visibility must be one of: private, public."
  }
}

variable "ado_repo_name" {
  type        = string
  description = "Azure DevOps Git repository name to create in the project."
  default     = "Azure-ArtifactSigning-DevOps"
}

variable "ado_pipeline_name" {
  type        = string
  description = "Azure DevOps YAML pipeline name to create in the project."
  default     = "artifact-signing-demo"
}

variable "ado_pipeline_yaml_path" {
  type        = string
  description = "Path to the YAML pipeline file in the repo."
  default     = "azure-pipelines.yml"
}

variable "ado_service_connection_name" {
  type        = string
  description = "AzureRM service connection name in Azure DevOps. Must match azureServiceConnection in azure-pipelines.yml."
  default     = "sc-artifact-signing"
}

variable "ado_service_connection_description" {
  type        = string
  description = "Description for the AzureRM service connection."
  default     = "Managed by Terraform"
}

variable "ado_service_endpoint_authentication_scheme" {
  type        = string
  description = "Authentication scheme for the AzureRM service connection. Use WorkloadIdentityFederation for secretless auth (requires org feature enabled), or ServicePrincipal for classic SP secret-based auth."
  default     = "WorkloadIdentityFederation"
  validation {
    condition     = contains(["WorkloadIdentityFederation", "ServicePrincipal"], var.ado_service_endpoint_authentication_scheme)
    error_message = "ado_service_endpoint_authentication_scheme must be one of: WorkloadIdentityFederation, ServicePrincipal."
  }
}

variable "ado_service_principal_client_id" {
  type        = string
  description = "Optional: an existing Entra application (client) ID to use for the Azure DevOps service connection. If null and ado_create_app=true, Terraform creates an app/SP and uses it."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.ado_enabled == false ||
      var.ado_create_app == true ||
      length(trimspace(var.ado_service_principal_client_id == null ? "" : var.ado_service_principal_client_id)) > 0
    )
    error_message = "When ado_enabled=true and ado_create_app=false, you must set ado_service_principal_client_id."
  }
}

variable "ado_service_principal_client_secret" {
  type        = string
  description = "Client secret for ServicePrincipal auth scheme. Prefer setting via TF_VAR_ado_service_principal_client_secret rather than terraform.tfvars."
  default     = null
  nullable    = true
  sensitive   = true

  validation {
    condition = (
      var.ado_enabled == false ||
      var.ado_service_endpoint_authentication_scheme != "ServicePrincipal" ||
      length(trimspace(var.ado_service_principal_client_secret == null ? "" : var.ado_service_principal_client_secret)) > 0
    )
    error_message = "When ado_enabled=true and ado_service_endpoint_authentication_scheme=ServicePrincipal, you must set ado_service_principal_client_secret (prefer TF_VAR_ado_service_principal_client_secret)."
  }
}

variable "ado_create_app" {
  type        = bool
  description = "Whether Terraform should create an Entra app registration + service principal for Azure DevOps."
  default     = true
}

variable "ado_wif_issuer" {
  type        = string
  description = "Optional override for the WIF issuer URL. If ado_enabled=true and Terraform creates the service connection, this can stay null (Terraform reads workload_identity_federation_issuer from Azure DevOps)."
  default     = null
  nullable    = true
}

variable "ado_wif_subject" {
  type        = string
  description = "Optional override for the WIF subject identifier. If ado_enabled=true and Terraform creates the service connection, this can stay null (Terraform reads workload_identity_federation_subject from Azure DevOps)."
  default     = null
  nullable    = true
}

variable "rbac_propagation_wait_duration" {
  type        = string
  description = "Optional wait after RBAC assignment to reduce propagation-related 403s (for example: 30s, 2m). Set to 0s to disable."
  default     = "30s"
}

variable "assign_signer_role_to_ado_sp" {
  type        = bool
  description = "If true, assigns 'Artifact Signing Certificate Profile Signer' to the Azure DevOps service principal at the certificate profile scope (requires certificate profile to exist)."
  default     = true
}

variable "assign_contributor_role_to_ado_sp" {
  type        = bool
  description = "If true, assigns Contributor at the resource group scope to the Azure DevOps service principal. Required if you want the pipeline to create the certificate profile (so you don't need a second terraform apply)."
  default     = true
}

variable "keyvault_enabled" {
  type        = bool
  description = "If true, Terraform will create an Azure Key Vault (RBAC-enabled) for storing pipeline secrets/variables."
  default     = true
}

variable "keyvault_name" {
  type        = string
  description = "Optional Key Vault name override (globally unique, 3-24 chars, alphanumeric). If null/empty and keyvault_enabled=true, Terraform generates a name."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.keyvault_name == null ||
      length(trimspace(var.keyvault_name == null ? "" : var.keyvault_name)) == 0 ||
      can(regex("^[a-zA-Z][0-9a-zA-Z]{2,23}$", trimspace(var.keyvault_name == null ? "" : var.keyvault_name)))
    )
    error_message = "keyvault_name must be 3-24 characters, alphanumeric, and start with a letter."
  }
}

variable "keyvault_sku_name" {
  type        = string
  description = "Key Vault SKU name."
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], lower(var.keyvault_sku_name))
    error_message = "keyvault_sku_name must be one of: standard, premium."
  }
}
