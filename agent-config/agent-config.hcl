pid_file = "./pidfile"

vault {
  address = "https://vault.dev.azure.nick-philbrook.sbx.hashidemos.io:8200"
  retry {
    num_retries = 5
  }
}

auto_auth {
  method {
    type = "azure"
    config = {
      role = "db-role"
      resource = "https://management.azure.com/"
    }
  }
}

cache {
  // An empty cache stanza still enables caching
}

template {
  source = "./db.creds.ctmpl"
  destination = "./db.creds"
}
