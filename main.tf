module "vault_hvd" {
  source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
  version = "0.1.5-alpha"
  #------------------------------------------------------------------------------
  # Common
  #------------------------------------------------------------------------------
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  create_resource_group = false
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  vault_fqdn            = "vault.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name}"

  #------------------------------------------------------------------------------
  # Networking
  #------------------------------------------------------------------------------
  vnet_id                         = module.vault_prereqs.vnet_id
  vault_subnet_id                 = module.vault_prereqs.vault_subnet_id
  lb_subnet_id                    = module.vault_prereqs.vault_subnet_id
  lb_is_internal                  = true
  create_vault_private_dns_record = true
  private_dns_zone_name           = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.zone_name
  private_dns_zone_rg             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name

  #------------------------------------------------------------------------------
  # Azure Key Vault installation secrets and unseal key
  #------------------------------------------------------------------------------
  prereqs_keyvault_rg_name               = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  prereqs_keyvault_name                  = module.vault_prereqs.key_vault_name
  vault_license_keyvault_secret_id       = module.vault_prereqs.vault_license_kv_secret_id
  vault_tls_cert_keyvault_secret_id      = module.vault_prereqs.vault_cert_kv_secret_id
  vault_tls_privkey_keyvault_secret_id   = module.vault_prereqs.vault_privkey_kv_secret_id
  vault_tls_ca_bundle_keyvault_secret_id = module.vault_prereqs.vault_ca_bundle_kv_secret_id

  vault_seal_azurekeyvault_vault_name      = module.vault_prereqs.key_vault_name
  vault_seal_azurekeyvault_unseal_key_name = azurerm_key_vault_key.vault_unseal_key.name

  #------------------------------------------------------------------------------
  # Compute
  #------------------------------------------------------------------------------
  vm_ssh_public_key = var.ssh_public_key
  # Default is 6
  #   vmss_vm_count     = var.vault_vms_count
  # default is "Standard_D2s_v5"
  # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6

  # Oracle plugin
  # This won't work until we override the custom_data shell script to install the client libs - not in RHEL repos
  #   vault_plugin_urls        = ["https://releases.hashicorp.com/vault-plugin-database-oracle/0.13.0+ent/vault-plugin-database-oracle_0.13.0+ent_linux_amd64.zip"]
  #   additional_package_names = ["oracle-instantclient-basiclite", "oracle-instantclient-sqlplus", "oracle-instantclient-devel"]
}
