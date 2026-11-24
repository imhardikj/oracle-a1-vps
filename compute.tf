# ---------------------------------------------------------------------------
# Compute: ARM Ampere A1 (Always Free pool: 4 OCPU / 24 GB / 200 GB total)
# ---------------------------------------------------------------------------

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Match on the image *name* rather than operating_system_version: standard (not
# Minimal) Ubuntu 24.04 Arm images are named Canonical-Ubuntu-24.04-aarch64-<date>.
data "oci_core_images" "ubuntu" {
  compartment_id   = local.compartment_id
  operating_system = "Canonical Ubuntu"
  shape            = "VM.Standard.A1.Flex"
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-aarch64-.*"]
    regex  = true
  }
}

locals {
  # try(): an empty lookup comes back as null; the precondition below turns that
  # into a readable error instead of "Attempt to index null value".
  image_id = var.image_ocid != null ? var.image_ocid : try(data.oci_core_images.ubuntu.images[0].id, null)

  user_data = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
    hostname           = var.instance_name
    username           = var.username
    tailscale_auth_key = var.tailscale_auth_key
    bootstrap_script   = file("${path.module}/cloud-init/bootstrap.sh")
  })
}

resource "oci_core_instance" "vps" {
  compartment_id      = local.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = local.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    display_name     = "${var.instance_name}-vnic"
    hostname_label   = var.instance_name
  }

  # No SSH keys at all: login is Tailscale SSH only (see cloud-init/bootstrap.sh).
  metadata = {
    user_data = base64encode(local.user_data)
  }

  lifecycle {
    precondition {
      condition     = local.image_id != null
      error_message = "No Ubuntu 24.04 aarch64 image found in this region. List what exists with: oci compute image list --compartment-id <tenancy-ocid> --operating-system \"Canonical Ubuntu\" --shape VM.Standard.A1.Flex --all --query 'data[].{name:\"display-name\",id:id}' --output table   then set image_ocid in terraform.tfvars."
    }

    # Bootstrap runs once. Without this, rotating the (single-use) Tailscale auth
    # key or editing cloud-init would destroy and recreate the VM. To re-provision
    # deliberately: terraform apply -replace=oci_core_instance.vps
    ignore_changes = [source_details[0].source_id, metadata]
  }
}
