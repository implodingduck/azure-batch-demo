terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.82.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
  }
  backend "azurerm" {

  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

locals {
  func_name = "batchfun${random_string.unique.result}"
  loc_for_naming = lower(replace(var.location, " ", ""))
  tags = {
    "managed_by" = "terraform"
    "repo"       = "azure-batch-demo"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.func_name}-${local.loc_for_naming}"
  location = var.location
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}


data "azurerm_client_config" "current" {}

data "azurerm_log_analytics_workspace" "default" {
  name                = "DefaultWorkspace-${data.azurerm_client_config.current.subscription_id}-EUS"
  resource_group_name = "DefaultResourceGroup-EUS"
} 


resource "azurerm_storage_account" "sa" {
  name                     = "satrigger${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

resource "azurerm_storage_container" "input" {
  name                  = "input"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "output" {
  name                  = "output"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

module "func" {
  source = "github.com/implodingduck/tfmodules//functionapp"
  func_name = "${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
  resource_group_location = azurerm_resource_group.rg.location
  working_dir = "../BatchFunc"
  // TODO add workspace_id for app insights
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    "TRIGGER_STORAGE_ACCOUNT" = azurerm_storage_account.sa.primary_blob_endpoint 
  }
  app_identity = [
      {
          type = "SystemAssigned"
          identity_ids = null
      }
  ]
  //tags = local.tags
}

resource "azurerm_role_assignment" "functosa" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = module.func.identity_principal_id

}


resource "azurerm_batch_account" "ba" {
  name                 = "ba${local.func_name}"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = azurerm_resource_group.rg.location
  pool_allocation_mode = "BatchService"
  identity {
      type = "SystemAssigned"
  }
  tags = local.tags
}
