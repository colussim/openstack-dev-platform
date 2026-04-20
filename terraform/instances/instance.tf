# ─── Data sources ─────────────────────────────────────────────────────────────

data "openstack_networking_network_v2" "private" {
  name = var.private_network_name
}

data "openstack_networking_network_v2" "public" {
  name = var.public_network_name
}

data "openstack_networking_subnet_v2" "private_subnet" {
  name = var.private_subnet_name
}

# ─── Keypair ──────────────────────────────────────────────────────────────────

resource "openstack_compute_keypair_v2" "centoskey" {
  name       = "centoskey"
  public_key = file(pathexpand(var.public_key_path))
}

# ─── Security group ───────────────────────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "web" {
  name        = "web-sg"
  description = "HTTP HTTPS SSH ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "cockpit" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9090
  port_range_max    = 9090
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}


# ─── Instance ─────────────────────────────────────────────────────────────────
resource "openstack_compute_instance_v2" "web" {
  name            = var.instance_name
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = openstack_compute_keypair_v2.centoskey.name
  security_groups = [openstack_networking_secgroup_v2.web.name]
  config_drive = true

  network {
    uuid = data.openstack_networking_network_v2.private.id
  }

   user_data = <<EOF
#cloud-config
password: ${var.instance_password}
chpasswd: 
  list: |
    root:${var.instance_password}
    admin:${var.instance_password}
  expire: False
ssh_pwauth: True

# Création de l'utilisateur admin
users:
  - name: admin
    groups: wheel
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    ssh_authorized_keys:
      - ${file(pathexpand(var.public_key_path))}



packages:
  - cockpit

runcmd:
  - systemctl enable --now cockpit.socket
  - systemctl disable --now firewalld
EOF

  depends_on = [openstack_networking_secgroup_v2.web]
}


# ─── Floating IP ──────────────────────────────────────────────────────────────

resource "openstack_networking_floatingip_v2" "web_fip" {
  pool = var.public_network_name
}

data "openstack_networking_port_v2" "web_port" {
  device_id  = openstack_compute_instance_v2.web.id
  network_id = data.openstack_networking_network_v2.private.id
}

resource "openstack_networking_floatingip_associate_v2" "web_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.web_fip.address
  port_id     = data.openstack_networking_port_v2.web_port.id
}
