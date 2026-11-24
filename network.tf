# ---------------------------------------------------------------------------
# Private networking: no public IP, no internet gateway, no ingress rules.
#
# Outbound-only internet comes from a NAT gateway (Tailscale and, later,
# cloudflared both dial out). Oracle services (OS repos, agent) use a service
# gateway.
# ---------------------------------------------------------------------------

locals {
  compartment_id = coalesce(var.compartment_ocid, var.tenancy_ocid)
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = local.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.instance_name}-vcn"
  dns_label      = "vpsvcn"
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.instance_name}-nat"
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.instance_name}-sgw"

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.instance_name}-private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

# Egress open, ingress intentionally empty. Replies to outbound connections are
# allowed because the rules are stateful.
resource "oci_core_security_list" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.instance_name}-private-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }
}

resource "oci_core_subnet" "private" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.instance_name}-private-subnet"
  dns_label                  = "private"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true # guardrail: a public IP can never be attached here
}
