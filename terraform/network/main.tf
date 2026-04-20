# ─── Public Network (provider network) ────────────────────────────────────────

resource "openstack_networking_network_v2" "public" {
  name           = var.public_network_name
  admin_state_up = true
  external       = true
  shared         = true
  segments {
    physical_network = "public"
    network_type     = "flat"
  }
}

resource "openstack_networking_subnet_v2" "public_subnet" {
  name            = var.public_subnet_name
  network_id      = openstack_networking_network_v2.public.id
  cidr            = var.public_cidr
  gateway_ip      = var.public_gateway
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
  allocation_pool {
    start = var.floating_ip_start
    end   = var.floating_ip_end
  }
}

# ─── Private Network (tenant network) ───────────────────────────────────────────

resource "openstack_networking_network_v2" "private" {
  name           = var.private_network_name
  admin_state_up = true
  shared         = false
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name            = var.private_subnet_name
  network_id      = openstack_networking_network_v2.private.id
  cidr            = var.private_cidr
  gateway_ip      = var.private_gateway
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
}

# ─── Router ──────────────────────────────────────────────────────────────────

resource "openstack_networking_router_v2" "router1" {
  name                = var.router_name
  admin_state_up      = true
  external_network_id = openstack_networking_network_v2.public.id
}

resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = openstack_networking_router_v2.router1.id
  subnet_id = openstack_networking_subnet_v2.private_subnet.id
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "default_rules" {
  name        = "default-rules"
  description = "Allow SSH and ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.default_rules.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.default_rules.id
}
