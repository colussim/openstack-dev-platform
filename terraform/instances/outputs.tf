output "instance_id" {
  value = openstack_compute_instance_v2.web.id
}

output "private_ip" {
  value = openstack_compute_instance_v2.web.access_ip_v4
}

output "floating_ip" {
  value = openstack_networking_floatingip_v2.web_fip.address
}

output "web_url" {
  value = "http://${openstack_networking_floatingip_v2.web_fip.address}"
}

output "ssh_command" {
  value = "ssh cloud-user@${openstack_networking_floatingip_v2.web_fip.address}"
}
