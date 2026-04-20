output "public_network_id" {
  description = "ID of the public network"
  value       = openstack_networking_network_v2.public.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = openstack_networking_subnet_v2.public_subnet.id
}

output "private_network_id" {
  description = "ID of the private network"
  value       = openstack_networking_network_v2.private.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = openstack_networking_subnet_v2.private_subnet.id
}

output "router_id" {
  description = "ID of the router"
  value       = openstack_networking_router_v2.router1.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = openstack_networking_secgroup_v2.default_rules.id
}

output "floating_ip_pool" {
  description = "Range of available floating IPs"
  value       = "${var.floating_ip_start} → ${var.floating_ip_end}"
}
