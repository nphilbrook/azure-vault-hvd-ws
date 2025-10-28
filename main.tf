module "vault_hvd" {
  source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
  version = "0.1.2-alpha"
  #------------------------------------------------------------------------------
  # Common
  #------------------------------------------------------------------------------
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.location
  create_resource_group = false
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.resource_group_name
  vault_fqdn            = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.zone_name}"

  #------------------------------------------------------------------------------
  # Networking
  #------------------------------------------------------------------------------
  vnet_id         = module.vault_prereqs.vnet_id
  vault_subnet_id = module.vault_prereqs.vault_subnet_id

  #------------------------------------------------------------------------------
  # Azure Key Vault installation secrets and unseal key
  #------------------------------------------------------------------------------
  prereqs_keyvault_rg_name               = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.resource_group_name
  prereqs_keyvault_name                  = module.vault_prereqs.key_vault_name
  vault_license_keyvault_secret_id       = module.vault_prereqs.vault_license_kv_secret_id
  vault_tls_cert_keyvault_secret_id      = module.vault_prereqs.vault_cert_kv_secret_id
  vault_tls_privkey_keyvault_secret_id   = module.vault_prereqs.vault_privkey_kv_secret_id
  vault_tls_ca_bundle_keyvault_secret_id = module.vault_prereqs.vault_ca_bundle_kv_secret_id

  vault_seal_azurekeyvault_vault_name      = "unseal-kv"
  vault_seal_azurekeyvault_unseal_key_name = "unseal-key"

  #------------------------------------------------------------------------------
  # Compute
  #------------------------------------------------------------------------------
  vm_ssh_public_key = var.ssh_public_key
  # Default is 6
  #   vmss_vm_count     = var.vault_vms_count
  # default is "Standard_D2s_v5"
  # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6
}
