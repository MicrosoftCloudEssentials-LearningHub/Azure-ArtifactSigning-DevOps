terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.13"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

provider "azuread" {}

provider "azuredevops" {
  # Provider blocks can't be conditional. Use a syntactically-valid placeholder URL when
  # Azure DevOps resources are disabled so non-ADO applies still work.
  # When ado_enabled=true and ado_org_service_url is null/empty, the azuredevops provider can
  # read AZDO_ORG_SERVICE_URL from the environment.
  org_service_url = var.ado_enabled ? (
    length(trimspace(var.ado_org_service_url == null ? "" : var.ado_org_service_url)) > 0 ? trimspace(var.ado_org_service_url) : null
  ) : "https://dev.azure.com/unused"
}
