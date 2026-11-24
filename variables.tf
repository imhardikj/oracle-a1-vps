variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy: only the value, starting with ocid1.tenancy."
  type        = string

  validation {
    condition     = startswith(var.tenancy_ocid, "ocid1.tenancy.")
    error_message = "tenancy_ocid must be just the OCID, starting with \"ocid1.tenancy.\". If you copied a line from ~/.oci/config, remove the leading \"tenancy=\"."
  }
}

variable "compartment_ocid" {
  description = "Compartment for all resources. Defaults to the tenancy (root) compartment."
  type        = string
  default     = null

  validation {
    condition     = var.compartment_ocid == null || startswith(var.compartment_ocid, "ocid1.compartment.") || startswith(var.compartment_ocid, "ocid1.tenancy.")
    error_message = "compartment_ocid must be a compartment OCID (ocid1.compartment....)."
  }
}

variable "instance_name" {
  description = "Instance display name, OCI hostname label and Linux/Tailscale hostname (e.g. \"vps\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.instance_name))
    error_message = "Use a valid hostname: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "username" {
  description = "Linux login user. Keep it equal to your Cloudflare Access email prefix if you plan to use Cloudflare browser SSH later."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.username)) && !contains(["root", "ubuntu"], var.username)
    error_message = "Use a valid Linux username (lowercase, digits, _ or -), not root or ubuntu."
  }
}

# --- Access --------------------------------------------------------------------

variable "tailscale_auth_key" {
  description = "Single-use, short-expiry, tagged Tailscale auth key. Pass via the TF_VAR_tailscale_auth_key environment variable (see README)."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.tailscale_auth_key, "tskey-")
    error_message = "That does not look like a Tailscale auth key (expected tskey-...)."
  }
}

# --- Sizing (Always Free A1 pool is 4 OCPU / 24 GB / 200 GB in total) ---------

variable "ocpus" {
  type    = number
  default = 4
}

variable "memory_in_gbs" {
  type    = number
  default = 24
}

variable "boot_volume_size_in_gbs" {
  type    = number
  default = 200

  validation {
    condition     = var.boot_volume_size_in_gbs >= 50
    error_message = "OCI boot volumes must be at least 50 GB."
  }
}

variable "image_ocid" {
  description = "OCID of the boot image: a Canonical Ubuntu aarch64 image (standard or Minimal) in your region. See the README for how to list them."
  type        = string

  validation {
    condition     = startswith(var.image_ocid, "ocid1.image.")
    error_message = "image_ocid must be an image OCID (ocid1.image.oc1.<region>....)."
  }
}

# --- Network -------------------------------------------------------------------

variable "vcn_cidr" {
  description = "Pick something that does not overlap other networks you use (e.g. an older VCN on 10.0.0.0/16)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.1.1.0/24"
}
