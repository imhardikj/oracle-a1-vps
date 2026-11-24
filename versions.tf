terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.8.0"
    }
  }

  # Native OCI backend. Credentials come from ~/.oci/config automatically.
  # bucket / namespace / key are supplied at init time (see backend.hcl.example)
  # so tenancy-specific values never get committed:
  #   terraform init -backend-config=backend.hcl
  backend "oci" {}
}
