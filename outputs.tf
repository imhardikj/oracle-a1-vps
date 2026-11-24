output "instance_id" {
  value = oci_core_instance.vps.id
}

output "private_ip" {
  description = "VCN-private address. Not reachable from the internet; use Tailscale."
  value       = oci_core_instance.vps.private_ip
}

output "ssh_via_tailscale" {
  description = "Run on a device that is on your tailnet, once the node has registered (~2-5 min after apply)."
  value       = "ssh ${var.username}@${var.instance_name}   # Tailscale SSH needs no key"
}

output "cloud_init_log_hint" {
  value = "On the VM: sudo cat /var/log/vps-bootstrap.log  (and /var/log/cloud-init-output.log)"
}
