terraform {
  required_version = "~>1.13"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.47"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~>2.23"
    }
    local = {
      source  = "hashicorp/local"
      version = "~>2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~>4.1"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~>0.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.7"
    }
  }
}
