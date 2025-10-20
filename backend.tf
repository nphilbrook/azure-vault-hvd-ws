terraform {
  cloud {
    organization = "philbrook"
    workspaces {
      name = "azure-vault-hvd-ws"
    }
  }
}