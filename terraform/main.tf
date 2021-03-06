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

resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.func_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled = false

  tags = local.tags
}

resource "azurerm_key_vault_access_policy" "sp" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Create",
    "Get",
    "Purge",
    "Recover",
    "Delete"
  ]

  secret_permissions = [
    "Set",
    "Purge",
    "Get",
    "List"
  ]

  certificate_permissions = [
    "Purge"
  ]

  storage_permissions = [
    "Purge"
  ]
}


resource "azurerm_key_vault_access_policy" "func" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = module.func.identity_principal_id
  
  key_permissions = [
    "get",
  ]

  secret_permissions = [
    "get",
    "list"
  ]
  
}

resource "azurerm_key_vault_secret" "satrigger" {
  depends_on = [
    azurerm_key_vault_access_policy.sp
  ]
  name         = "satriggerconnectionstring"
  value        = azurerm_storage_account.sa.primary_blob_connection_string
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "baaccesskey" {
  depends_on = [
    azurerm_key_vault_access_policy.sp
  ]
  name         = "baaccesskey"
  value        = azurerm_batch_account.ba.primary_access_key
  key_vault_id = azurerm_key_vault.kv.id
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
    "TRIGGER_STORAGE_ACCOUNT" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=${azurerm_key_vault_secret.satrigger.name})"
    "BATCH_ACCOUNT_ENDPOINT" = "https://${azurerm_batch_account.ba.account_endpoint}"
    "BATCH_ACCOUNT_NAME" = "ba${local.func_name}"
    "BATCH_ACCOUNT_KEY" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=${azurerm_key_vault_secret.baaccesskey.name})"
    "BATCH_POOL_ID" = "demopool"
    "BATCH_JOB_ID" = "${local.func_name}-job"
    "TRIGGER_STORAGE_ACCOUNT_NAME" = "satrigger${random_string.unique.result}"
  }
  app_identity = [
      {
          type = "SystemAssigned"
          identity_ids = null
      }
  ]
  //tags = local.tags
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

resource "azurerm_user_assigned_identity" "test" {
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  name = "ba${local.func_name}-demopool-id"
}

resource "azurerm_role_assignment" "pooltosa" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.test.principal_id

}


resource "azurerm_batch_pool" "pool" {
  name                = "demopool"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_batch_account.ba.name
  node_agent_sku_id   = "batch.node.ubuntu 20.04"
  vm_size             = "Standard_DS1_V2"
  storage_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.test.id
    ] 
  }

  fixed_scale {
    target_dedicated_nodes = 0
    target_low_priority_nodes = 1
  }
  start_task {
    command_line         = "/bin/bash -c \"sudo apt-get -y update && sudo apt-get install -y python3 jq && curl -O https://raw.githubusercontent.com/implodingduck/ado-agent-cloud-init/main/setup.sh && chmod +x setup.sh && ./setup.sh\""
    max_task_retry_count = 1
    wait_for_success     = true

    environment = {
      env = "TEST"
    }

    user_identity {
      auto_user {
        elevation_level = "Admin"
        scope           = "Task"
      }
    }
  }
}

resource "azurerm_batch_job" "job" {
  name          = "${local.func_name}-job"
  batch_pool_id = azurerm_batch_pool.pool.id
}