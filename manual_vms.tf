# RUNNING STATE:
# 3 has the successful config
# The rest are tabula rasa

locals {
  resource_group_name = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.resource_group_name
}

resource "azurerm_network_interface" "vault_nic" {
  count               = var.vmss_vm_count
  resource_group_name = local.resource_group_name
  location            = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  name                = "${var.friendly_name_prefix}-vault-vm-nic-${count.index}"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vault_prereqs.vault_subnet_id
    private_ip_address_allocation = "Dynamic"
    # TODO: this vv
    # load_balancer_backend_address_pool_ids = [
    #   azurerm_lb_backend_address_pool.vault_servers[0].id,
    # ]
  }
  tags = merge(
    # CRITICAL - this tag is critical for the auto-join feature to work
    { "VaultCluster" = var.friendly_name_prefix },
    local.default_tags
  )
}

resource "azurerm_lb_backend_address_pool_address" "vault_pool_address" {
  count                   = var.vmss_vm_count
  name                    = "${var.friendly_name_prefix}-vault-lb-backend-${count.index}"
  backend_address_pool_id = "/subscriptions/9d1e3560-fd29-4207-be8f-c6f9f0f1b64d/resourceGroups/dev-centralus/providers/Microsoft.Network/loadBalancers/dev-vault-lb/backendAddressPools/dev-vault-backend"
  virtual_network_id      = module.vault_prereqs.vnet_id
  ip_address              = azurerm_network_interface.vault_nic[count.index].private_ip_address
}

data "azurerm_platform_image" "latest_os_image" {
  location  = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  publisher = "RedHat"
  offer     = "RHEL"
  sku       = "95_gen2"
}

resource "azurerm_linux_virtual_machine" "vault_vm" {
  count               = var.vmss_vm_count
  name                = "${var.friendly_name_prefix}-vault-${count.index}"
  resource_group_name = local.resource_group_name
  location            = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location

  size           = "Standard_D2s_v5"
  admin_username = "vaultadmin"

  zone = element(tolist(["1", "2", "3"]), count.index)
  # health_probe_id     = var.create_lb == true ? azurerm_lb_probe.vault[0].id : null

  # custom_data = base64encode(templatefile("${local.custom_startup_script_template}", local.custom_data_args))

  identity {
    type         = "UserAssigned"
    identity_ids = ["/subscriptions/9d1e3560-fd29-4207-be8f-c6f9f0f1b64d/resourceGroups/dev-centralus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dev-vault-msi"]
  }

  admin_ssh_key {
    username   = "vaultadmin"
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "95_gen2"
    version   = data.azurerm_platform_image.latest_os_image.version
  }

  network_interface_ids = [
    azurerm_network_interface.vault_nic[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = "64"
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-vault-${count.index}" },
    { "VaultCluster" = "dev" },
    local.default_tags
  )
}

resource "azurerm_managed_disk" "vault_data" {
  count                = var.vmss_vm_count
  name                 = "${var.friendly_name_prefix}-vault-data-disk-${count.index}"
  location             = data.tfe_outputs.azure_core_infra_outputs.values.environment_info.centralus.location
  resource_group_name  = local.resource_group_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "200"
  zone                 = element(tolist(["1", "2", "3"]), count.index)

  tags = local.default_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "vault_data_attachment" {
  count              = var.vmss_vm_count
  managed_disk_id    = azurerm_managed_disk.vault_data[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.vault_vm[count.index].id
  lun                = "0"
  caching            = "ReadWrite"
}
