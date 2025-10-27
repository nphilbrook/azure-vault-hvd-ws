locals {
  default_tags = {
    "created-by"       = "terraform"
    "source-workspace" = var.TFC_WORKSPACE_SLUG
  }
}
