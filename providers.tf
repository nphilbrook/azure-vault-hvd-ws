provider "azurerm" {
  use_cli                         = false
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.KeyVault"]

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

provider "local" {
}

provider "tls" {
}

provider "random" {
}

provider "tfe" {
  organization = var.tfe_organization
}
