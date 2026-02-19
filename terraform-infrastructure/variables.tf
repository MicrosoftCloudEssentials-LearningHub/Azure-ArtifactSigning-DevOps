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

  validation {
    condition = (
      length(var.code_signing_account_name) >= 3 &&
      length(var.code_signing_account_name) <= 24 &&
      can(regex("^[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*$", var.code_signing_account_name))
    )
    error_message = "code_signing_account_name must be 3-24 chars, start with a letter, contain only letters/numbers/hyphens, and not contain underscores. Example: aasdemo-abc123."
  }
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

variable "rbac_propagation_wait_duration" {
  type        = string
  description = "Optional wait after RBAC assignment to reduce propagation-related 403s (for example: 30s, 2m). Set to 0s to disable."
  default     = "30s"
}

variable "assign_identity_verifier_role_to_current" {
  type        = bool
  description = "If true, assigns 'Artifact Signing Identity Verifier' on the Artifact Signing account to the identity running terraform apply. Required to complete identity validation in the Azure portal."
  default     = true
}

variable "github_enabled" {
  type        = bool
  description = "If true, Terraform will create an Entra app/SP + federated identity credential (OIDC) for GitHub Actions to authenticate to Azure without secrets."
  default     = false
}

variable "github_autodetect" {
  type        = bool
  description = "If true and github_enabled=true, Terraform will attempt to auto-detect github_owner/github_repo/github_ref from the local git repo during plan/apply (via the external data source)."
  default     = true
}

variable "github_owner" {
  type        = string
  description = "GitHub repository owner/org (used for the federated identity subject). Required when github_enabled=true."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.github_enabled == false || var.github_autodetect == true || (
        length(trimspace(var.github_owner == null ? "" : var.github_owner)) > 0 &&
        !strcontains(upper(trimspace(var.github_owner == null ? "" : var.github_owner)), "REPLACE_ME")
      )
    )
    error_message = "When github_enabled=true you must set github_owner (and it must not be REPLACE_ME)."
  }
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (used for the federated identity subject). Required when github_enabled=true."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.github_enabled == false || var.github_autodetect == true || (
        length(trimspace(var.github_repo == null ? "" : var.github_repo)) > 0 &&
        !strcontains(upper(trimspace(var.github_repo == null ? "" : var.github_repo)), "REPLACE_ME")
      )
    )
    error_message = "When github_enabled=true you must set github_repo (and it must not be REPLACE_ME)."
  }
}

variable "github_ref" {
  type        = string
  description = "GitHub ref for the federated identity credential subject. Default is refs/heads/main."
  default     = "refs/heads/main"

  validation {
    condition = (
      var.github_enabled == false || var.github_autodetect == true || can(regex("^refs/heads/[^\\s]+$", trimspace(var.github_ref)))
    )
    error_message = "github_ref must look like refs/heads/<branch> when github_enabled=true."
  }
}

variable "github_app_display_name" {
  type        = string
  description = "Display name for the Entra app registration used by GitHub Actions (OIDC)."
  default     = "github-artifact-signing-demo"
}

variable "assign_signer_role_to_github_sp" {
  type        = bool
  description = "If true, assigns 'Artifact Signing Certificate Profile Signer' to the GitHub Actions service principal at the certificate profile scope (requires certificate profile to exist)."
  default     = true
}

variable "assign_signer_role_to_github_sp_at_account_scope" {
  type        = bool
  description = "If true, assigns 'Artifact Signing Certificate Profile Signer' to the GitHub Actions service principal at the Code Signing ACCOUNT scope. This is broader than profile-scope; prefer false for least privilege."
  default     = false
}

variable "assign_contributor_role_to_github_sp" {
  type        = bool
  description = "If true, assigns Contributor at the resource group scope to the GitHub Actions service principal. Required if you want the GitHub workflow to create the certificate profile (so you don't need a second terraform apply)."
  default     = false
}

variable "keyvault_enabled" {
  type        = bool
  description = "If true, Terraform will create an Azure Key Vault (RBAC-enabled) for storing pipeline secrets/variables."
  default     = true
}

variable "keyvault_populate_secrets" {
  type        = bool
  description = "If true, Terraform writes the artifactSigning* secrets into Key Vault during apply (requires data-plane RBAC on the vault). Set false for least privilege if you prefer managing secrets outside Terraform."
  default     = true
}

variable "keyvault_grant_keys_access_to_current" {
  type        = bool
  description = "If true, grants the identity running terraform apply permission to view/use Key Vault Keys via RBAC (assigns 'Key Vault Crypto User'). Default false (least privilege)."
  default     = false
}

variable "keyvault_grant_certificates_access_to_current" {
  type        = bool
  description = "If true, grants the identity running terraform apply permission to view/use Key Vault Certificates via RBAC (assigns 'Key Vault Certificates User'). Default false (least privilege)."
  default     = false
}

variable "keyvault_grant_administrator_to_current" {
  type        = bool
  description = "If true, grants the identity running terraform apply full Key Vault administration rights via RBAC (assigns 'Key Vault Administrator'). Broad; prefer the narrower key/cert toggles when possible. Default false."
  default     = false
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
