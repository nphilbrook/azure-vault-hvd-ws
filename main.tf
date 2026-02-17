module "vault_hvd" {
  source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
  version = "0.2.1-alpha"
  #------------------------------------------------------------------------------
  # Common
  #------------------------------------------------------------------------------
  friendly_name_prefix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  create_resource_group = false
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  vault_fqdn            = "vault-primary.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  common_tags           = local.default_tags

  #------------------------------------------------------------------------------
  # Networking
  #------------------------------------------------------------------------------
  vnet_id                                            = module.vault_prereqs.vnet_id
  vault_subnet_id                                    = module.vault_prereqs.vault_subnet_id
  lb_subnet_id                                       = module.vault_prereqs.vault_subnet_id
  lb_is_internal                                     = true
  create_vault_private_dns_record                    = true
  private_dns_zone_name                              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  private_dns_zone_rg                                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  create_private_dns_zone_vnet_link                  = true
  create_private_dns_zone_vnet_link_autoregistration = true

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
  vm_os_image       = "redhat9"
  vm_admin_username = "vaultadmin"
  vm_domain_suffix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name

  vmss_vm_count = 3
  # default is "Standard_D2s_v5"
  # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6

  # Oracle plugin
  # This won't work until we override the custom_data shell script to install the client libs - not in RHEL repos
  #   vault_plugin_urls        = ["https://releases.hashicorp.com/vault-plugin-database-oracle/0.13.0+ent/vault-plugin-database-oracle_0.13.0+ent_linux_amd64.zip"]
  #   additional_package_names = ["oracle-instantclient-basiclite", "oracle-instantclient-sqlplus", "oracle-instantclient-devel"]

  vault_version = "1.21.3+ent"
  # custom_startup_script_template = "install_vault_azure_rhel.sh.tpl"
}

# 2nd DR cluster to validate some PKI assumptions
module "vault_hvd_dr2" {
  source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
  version = "0.2.1-alpha"
  #------------------------------------------------------------------------------
  # Common
  #------------------------------------------------------------------------------
  friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.environment}dr2"
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.location
  create_resource_group = false
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.resource_group_name
  vault_fqdn            = "vault-dr.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  common_tags           = local.default_tags

  #------------------------------------------------------------------------------
  # Networking
  #------------------------------------------------------------------------------
  vnet_id                         = module.vault_prereqs_dr.vnet_id
  vault_subnet_id                 = module.vault_prereqs_dr.vault_subnet_id
  lb_subnet_id                    = module.vault_prereqs_dr.vault_subnet_id
  lb_is_internal                  = true
  create_vault_private_dns_record = true
  private_dns_zone_name           = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  private_dns_zone_rg             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  # Done above in primary DR. But if I delete that one, gotta bring these back!
  create_private_dns_zone_vnet_link                  = true
  create_private_dns_zone_vnet_link_autoregistration = true

  #------------------------------------------------------------------------------
  # Azure Key Vault installation secrets and unseal key
  #------------------------------------------------------------------------------
  prereqs_keyvault_rg_name             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.dr.resource_group_name
  prereqs_keyvault_name                = module.vault_prereqs_dr.key_vault_name
  vault_license_keyvault_secret_id     = module.vault_prereqs_dr.vault_license_kv_secret_id
  vault_tls_cert_keyvault_secret_id    = module.vault_prereqs_dr.vault_cert_kv_secret_id
  vault_tls_privkey_keyvault_secret_id = module.vault_prereqs_dr.vault_privkey_kv_secret_id
  # This is not needed if your certs are publicly trusted
  # Not verified, but if you certs are also trusted by all compute nodes in the ecosystem, even if not public,
  # this should *also* not be needed
  vault_tls_ca_bundle_keyvault_secret_id = null

  vault_seal_azurekeyvault_vault_name      = module.vault_prereqs_dr.key_vault_name
  vault_seal_azurekeyvault_unseal_key_name = azurerm_key_vault_key.vault_unseal_key_dr.name

  #------------------------------------------------------------------------------
  # Compute
  #------------------------------------------------------------------------------
  vm_ssh_public_key = var.ssh_public_key
  vm_os_image       = "redhat9"
  vm_admin_username = "vaultadmin"
  vm_domain_suffix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  # Default is 6
  vmss_vm_count = 3
  # default is "Standard_D2s_v5"
  # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6

  # Oracle plugin
  # This won't work until we override the custom_data shell script to install the client libs - not in RHEL repos
  #   vault_plugin_urls        = ["https://releases.hashicorp.com/vault-plugin-database-oracle/0.13.0+ent/vault-plugin-database-oracle_0.13.0+ent_linux_amd64.zip"]
  #   additional_package_names = ["oracle-instantclient-basiclite", "oracle-instantclient-sqlplus", "oracle-instantclient-devel"]
  vault_version = "1.21.3+ent"
  # custom_startup_script_template = "install_vault_azure_rhel.sh.tpl"
}

resource "azurerm_private_dns_cname_record" "vault" {
  name                = "vault"
  resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  zone_name           = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  ttl                 = 60
  record              = "vault-primary.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  tags                = local.default_tags
}

### testing firewalld change on other OSes
module "vault_hvd_rhel8" {
  source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
  version = "0.2.1-alpha"
  #------------------------------------------------------------------------------
  # Common
  #------------------------------------------------------------------------------
  friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment}r8"
  location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  create_resource_group = false
  resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
  vault_fqdn            = "vault-foo.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
  common_tags           = local.default_tags

  #------------------------------------------------------------------------------
  # Networking
  #------------------------------------------------------------------------------
  vnet_id                                            = module.vault_prereqs.vnet_id
  vault_subnet_id                                    = module.vault_prereqs.vault_subnet_id
  lb_subnet_id                                       = module.vault_prereqs.vault_subnet_id
  lb_is_internal                                     = true
  create_vault_private_dns_record                    = true
  private_dns_zone_name                              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
  private_dns_zone_rg                                = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
  create_private_dns_zone_vnet_link                  = false
  create_private_dns_zone_vnet_link_autoregistration = true

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
  vm_os_image       = "redhat8"
  vm_admin_username = "vaultadmin"
  vm_domain_suffix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name

  vmss_vm_count = 3
  # default is "Standard_D2s_v5"
  # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6

  # Oracle plugin
  # This won't work until we override the custom_data shell script to install the client libs - not in RHEL repos
  #   vault_plugin_urls        = ["https://releases.hashicorp.com/vault-plugin-database-oracle/0.13.0+ent/vault-plugin-database-oracle_0.13.0+ent_linux_amd64.zip"]
  #   additional_package_names = ["oracle-instantclient-basiclite", "oracle-instantclient-sqlplus", "oracle-instantclient-devel"]

  vault_version = "1.21.3+ent"
  # custom_startup_script_template = "install_vault_azure_rhel.sh.tpl"
}

# module "vault_hvd_ubuntu22" {
#   source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
#   version = "0.2.1-alpha"
#   #------------------------------------------------------------------------------
#   # Common
#   #------------------------------------------------------------------------------
#   friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment}u22"
#   location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
#   create_resource_group = false
#   resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   vault_fqdn            = "vault-bar.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
#   common_tags           = local.default_tags

#   #------------------------------------------------------------------------------
#   # Networking
#   #------------------------------------------------------------------------------
#   vnet_id                           = module.vault_prereqs.vnet_id
#   vault_subnet_id                   = module.vault_prereqs.vault_subnet_id
#   lb_subnet_id                      = module.vault_prereqs.vault_subnet_id
#   lb_is_internal                    = true
#   create_vault_private_dns_record   = true
#   private_dns_zone_name             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
#   private_dns_zone_rg               = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
#   create_private_dns_zone_vnet_link = false

#   #------------------------------------------------------------------------------
#   # Azure Key Vault installation secrets and unseal key
#   #------------------------------------------------------------------------------
#   prereqs_keyvault_rg_name               = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   prereqs_keyvault_name                  = module.vault_prereqs.key_vault_name
#   vault_license_keyvault_secret_id       = module.vault_prereqs.vault_license_kv_secret_id
#   vault_tls_cert_keyvault_secret_id      = module.vault_prereqs.vault_cert_kv_secret_id
#   vault_tls_privkey_keyvault_secret_id   = module.vault_prereqs.vault_privkey_kv_secret_id
#   vault_tls_ca_bundle_keyvault_secret_id = module.vault_prereqs.vault_ca_bundle_kv_secret_id

#   vault_seal_azurekeyvault_vault_name      = module.vault_prereqs.key_vault_name
#   vault_seal_azurekeyvault_unseal_key_name = azurerm_key_vault_key.vault_unseal_key.name

#   #------------------------------------------------------------------------------
#   # Compute
#   #------------------------------------------------------------------------------
#   vm_ssh_public_key = var.ssh_public_key
#   vm_os_image       = "ubuntu2204"
#   vm_admin_username = "vaultadmin"
#   vm_domain_suffix  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name

#   vmss_vm_count = 3
#   # default is "Standard_D2s_v5"
#   # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6

#   # Oracle plugin
#   # This won't work until we override the custom_data shell script to install the client libs - not in RHEL repos
#   #   vault_plugin_urls        = ["https://releases.hashicorp.com/vault-plugin-database-oracle/0.13.0+ent/vault-plugin-database-oracle_0.13.0+ent_linux_amd64.zip"]
#   #   additional_package_names = ["oracle-instantclient-basiclite", "oracle-instantclient-sqlplus", "oracle-instantclient-devel"]

#   vault_version = "1.21.3+ent"
#   # custom_startup_script_template = "install_vault_azure_rhel.sh.tpl"
# }

# module "vault_hvd_ubuntu24" {
#   source  = "app.terraform.io/philbrook/vault-enterprise-hvd/azurerm"
#   version = "0.2.1-alpha"
#   #------------------------------------------------------------------------------
#   # Common
#   #------------------------------------------------------------------------------
#   friendly_name_prefix  = "${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.environment}u24"
#   location              = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
#   create_resource_group = false
#   resource_group_name   = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   vault_fqdn            = "vault-baz.${data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name}"
#   common_tags           = local.default_tags

#   #------------------------------------------------------------------------------
#   # Networking
#   #------------------------------------------------------------------------------
#   vnet_id                           = module.vault_prereqs.vnet_id
#   vault_subnet_id                   = module.vault_prereqs.vault_subnet_id
#   lb_subnet_id                      = module.vault_prereqs.vault_subnet_id
#   lb_is_internal                    = true
#   create_vault_private_dns_record   = true
#   private_dns_zone_name             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.zone_name
#   private_dns_zone_rg               = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.global.resource_group_name
#   create_private_dns_zone_vnet_link = false

#   #------------------------------------------------------------------------------
#   # Azure Key Vault installation secrets and unseal key
#   #------------------------------------------------------------------------------
#   prereqs_keyvault_rg_name               = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
#   prereqs_keyvault_name                  = module.vault_prereqs.key_vault_name
#   vault_license_keyvault_secret_id       = module.vault_prereqs.vault_license_kv_secret_id
#   vault_tls_cert_keyvault_secret_id      = module.vault_prereqs.vault_cert_kv_secret_id
#   vault_tls_privkey_keyvault_secret_id   = module.vault_prereqs.vault_privkey_kv_secret_id
#   vault_tls_ca_bundle_keyvault_secret_id = module.vault_prereqs.vault_ca_bundle_kv_secret_id

#   vault_seal_azurekeyvault_vault_name      = module.vault_prereqs.key_vault_name
#   vault_seal_azurekeyvault_unseal_key_name = azurerm_key_vault_key.vault_unseal_key.name

#   #------------------------------------------------------------------------------
#   # Compute
#   #------------------------------------------------------------------------------
#   vm_ssh_public_key = var.ssh_public_key
#   vm_os_image       = "ubuntu2404"
#   vm_admin_username = "vaultadmin"

#   vmss_vm_count = 3
#   # default is "Standard_D2s_v5"
#   # vm_sku            = "Standard_D2as_v6" # try Standard_D2ds_v6

#   # Oracle plugin
#   # This won't work until we override the custom_data shell script to install the client libs - not in RHEL repos
#   #   vault_plugin_urls        = ["https://releases.hashicorp.com/vault-plugin-database-oracle/0.13.0+ent/vault-plugin-database-oracle_0.13.0+ent_linux_amd64.zip"]
#   #   additional_package_names = ["oracle-instantclient-basiclite", "oracle-instantclient-sqlplus", "oracle-instantclient-devel"]

#   vault_version = "1.21.3+ent"
#   # custom_startup_script_template = "install_vault_azure_rhel.sh.tpl"
# }
