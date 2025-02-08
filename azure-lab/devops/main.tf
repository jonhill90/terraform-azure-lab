# ----------------------------------------
# GitHub Repository (local)
# ----------------------------------------
module "github_repo" {
  source = "../../modules/github/repo"

  repo_name          = "terraform-labs"
  description        = "Terraform repository for managing cloud infrastructure, security policies, and automation workflows."
  visibility         = "public"
  auto_init          = true
  has_issues         = true
  has_projects       = false
  has_wiki           = false
  allow_merge_commit = true
  allow_squash_merge = true
  allow_rebase_merge = true
}

# ----------------------------------------
# Resource Groups (local)
# ----------------------------------------
resource "azurerm_resource_group" "devops" {
  name     = "DevOps"
  location = "eastus"
  provider = azurerm.management

  tags = {
    environment = var.environment
    owner       = var.owner
    project     = var.project
  }
}

# --------------------------------------------------
# Secure Vault (local)
# --------------------------------------------------
module "devops_vault" {
  source                     = "../../modules/azurerm/security/vault"
  key_vault_name             = substr("${var.environment}-${var.project}", 0, 24)
  resource_group_name        = azurerm_resource_group.devops.name
  location                   = "eastus"
  sku_name                   = "standard"
  purge_protection           = false
  soft_delete_retention_days = 90

  tenant_id = var.tenant_id

  providers = {
    azurerm = azurerm.management
  }

  depends_on = [azurerm_resource_group.devops] # Ensure Resource Group exists first
}

# --------------------------------------------------
# Secure Vault Access (local / Azure Admin Account)
# --------------------------------------------------
module "vault_access" {
  source       = "../../modules/azurerm/security/vault-access"
  key_vault_id = module.devops_vault.key_vault_id

  access_policies = [
    {
      tenant_id               = var.tenant_id
      object_id               = var.admin_object_id
      key_permissions         = ["Get", "List"]
      secret_permissions      = ["Get", "List", "Set", "Delete"]
      certificate_permissions = ["Get", "List"]
    }
  ]

  providers = {
    azurerm = azurerm.management
  }

  depends_on = [module.devops_vault] # Ensure Vault exists before setting access
}

# --------------------------------------------------
# AzureAD Service Principal - DevOps (local)
# --------------------------------------------------
module "devops_service_principal" {
  source                = "../../modules/azuread/service-principle"
  name                  = "devops"
  password_lifetime     = "8760h"
  key_vault_id          = module.devops_vault.key_vault_id
  store_secret_in_vault = true

  providers = {
    azuread = azuread.impressiveit
    azurerm = azurerm.management
  }

  tags = {
    environment = var.environment
    owner       = var.owner
    project     = var.project
  }

  depends_on = [module.devops_vault, module.vault_access] # Ensure Vault and Admin Access exist
}

# --------------------------------------------------
# Service Principal Role Assignment - DevOps (local)
# --------------------------------------------------
module "devops_sp_role_assignment" {
  source       = "../../modules/azurerm/security/role-assignment"
  role_scope   = "/subscriptions/${var.management_subscription_id}"
  role_name    = "Contributor"
  principal_id = module.devops_service_principal.service_principal_id

  providers = {
    azurerm = azurerm.management
  }

  depends_on = [module.devops_service_principal] # Ensure SP exists before assigning roles
}

# --------------------------------------------------
# Secure Vault Access (Service Principal)
# --------------------------------------------------
module "sp_vault_access" {
  source       = "../../modules/azurerm/security/vault-access"
  key_vault_id = module.devops_vault.key_vault_id

  access_policies = [
    {
      tenant_id               = var.tenant_id
      object_id               = module.devops_service_principal.service_principal_id
      key_permissions         = ["Get", "List"]
      secret_permissions      = ["Get", "List", "Set", "Delete"]
      certificate_permissions = ["Get", "List"]
    }
  ]

  providers = {
    azurerm = azurerm.management
  }

  depends_on = [
    module.devops_vault,            # Ensure Vault exists before setting access
    module.devops_service_principal # Ensure SP exists before granting access
  ]
}
/*
# --------------------------------------------------
# Azure DevOps API Permissions (local)
# --------------------------------------------------
module "devops_api_permissions" {
  source = "../../modules/azuread/api-permissions"

  service_principal_object_id = module.devops_service_principal.service_principal_id

  api_permissions = [
    {
      resource_object_id = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps API
      app_role_id        = "6f911362-37a4-46fc-bb2c-049e57ec707a" # Build.ReadWrite
    },
    {
      resource_object_id = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps API
      app_role_id        = "1a84c918-91c8-4700-94ea-d4465800fb01" # Release.ReadWrite
    },
    {
      resource_object_id = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps API
      app_role_id        = "b33be1eb-6b7b-49eb-96b6-2b0c47b81e5e" # ServiceEndpoint.ReadWrite
    },
    {
      resource_object_id = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps API
      app_role_id        = "cb8682be-02be-48a3-89ec-8c54b1b0c341" # Project.ReadWrite
    }
  ]

  providers = {
    azuread = azuread.impressiveit
  }

  depends_on = [module.devops_service_principal] # Ensure SP exists before assigning permissions
}
*/