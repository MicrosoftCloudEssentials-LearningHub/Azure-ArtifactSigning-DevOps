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
  org_service_url = var.ado_enabled ? var.ado_org_service_url : "https://dev.azure.com/unused"
}
