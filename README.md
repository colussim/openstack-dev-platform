# OpenStack Lab on Apple Silicon with Multipass & Terraform

A complete guide to deploy a production-like OpenStack test environment on an Apple Silicon Mac using Multipass virtualization, Devstack, OVN networking, and Terraform infrastructure-as-code.

---

## Table of contents

- [Introduction](#introduction)
- [OpenStack core services](#openstack-core-services)
- [Lab architecture](#lab-architecture)
- [Prerequisites](#prerequisites)
- [Multipass VM setup](#multipass-vm-setup)
- [Devstack installation](#devstack-installation)
- [ARM64-specific fixes](#arm64-specific-fixes)
- [Terraform — network workload](#terraform--network-workload)
- [Terraform — instances workload](#terraform--instances-workload)
- [Known issues and fixes](#known-issues-and-fixes)
- [Conclusion](#conclusion)

---

## Introduction

OpenStack is an open-source cloud computing platform that allows you to build and manage both public and private clouds. It provides Infrastructure-as-a-Service (IaaS) capabilities equivalent to AWS, Azure, or OCI — virtual machines, software-defined networking, block storage, object storage, and load balancing — all managed through a unified API and web dashboard.

This project demonstrates how to run a fully functional OpenStack environment on a Mac Studio M1 Pro using Multipass as the hypervisor layer. The goal is to provide a realistic test platform where infrastructure can be provisioned, tested, and torn down using the same Terraform workflows you would use against a production OpenStack cloud.

---

## OpenStack core services

OpenStack is composed of loosely coupled services, each responsible for a specific infrastructure concern. They communicate through REST APIs and a shared message bus (RabbitMQ).

### Identity — Keystone

Keystone is the authentication and authorization backbone of OpenStack. Every API call to any service must first pass through Keystone to obtain a token. It manages users, projects (tenants), roles, and domains. It also acts as a service catalog, listing the endpoints for every OpenStack service.

### Compute — Nova

Nova orchestrates the lifecycle of virtual machines. It decides which physical host runs each VM (scheduling), calls libvirt/QEMU to create the instance, and manages operations like resize, migrate, and snapshot. Nova does not handle networking or storage directly — it delegates to Neutron and Cinder via their APIs.

### Networking — Neutron

Neutron provides Software-Defined Networking (SDN) for OpenStack. It manages virtual networks, subnets, routers, security groups, floating IPs, and load balancers. In this lab we use OVN (Open Virtual Network) as the Neutron backend, which implements L2 and L3 switching entirely in the kernel via Open vSwitch flow tables — no separate network namespace agents needed.

### Image — Glance

Glance is the image registry. It stores and serves VM disk images (qcow2, raw, vmdk) that Nova uses to boot instances. Images carry metadata properties that inform Nova about the hardware requirements of the guest — architecture, machine type, firmware type, disk bus.

### Block storage — Cinder

Cinder provides persistent block storage volumes that can be attached to and detached from running instances, similar to AWS EBS. Volumes survive instance termination and can be snapshotted or cloned.

### Dashboard — Horizon

Horizon is the web-based graphical interface for OpenStack. It wraps the underlying APIs in a browser UI, providing access to all resources — instances, networks, images, volumes, load balancers — for both administrators and regular users.

### Load balancer — Octavia

Octavia is OpenStack's Load Balancer as a Service (LBaaS). In this lab it runs with the OVN driver, meaning load balancing rules are implemented directly in OVN flow tables without spawning separate Amphora VM instances. A load balancer exposes a Virtual IP (VIP) that distributes traffic across a pool of backend instances.

### Placement

Placement tracks resource inventories and allocations across compute nodes — vCPUs, memory, disk, and custom resource classes. Nova consults Placement during scheduling to find hosts that can satisfy a VM's resource requirements.

---

## Lab architecture

```
Local network (192.168.0.x)
       |
       | static route: 192.168.2.0/24 → Mac Studio
       |
Mac Studio M1 Pro (192.168.0.13)
  ├── en0           — physical ethernet (192.168.0.x)
  ├── bridge100     — Multipass NAT network (192.168.2.1)
  └── enp0s2 (VM)  — attached to OVS br-ex for OVN routing
       |
Multipass VM: openstack-adm
  ├── enp0s1        — management SSH (192.168.2.14)  ← never touched by OVS
  ├── enp0s2        — OVS br-ex port  ← used by OVN for floating IPs
  └── OpenStack (Devstack stable/2026.1)
        ├── Keystone  · Horizon  · Glance
        ├── Nova      · Placement
        ├── Neutron   · OVN · br-int · br-ex
        ├── Cinder
        └── Octavia   · OVN driver · o-hm0 (172.16.0.1)

Network topology (OpenStack tenant)
  public subnet    192.168.0.0/24   ← floating IPs 192.168.0.80–89
        |
     router1       192.168.0.x ↔ 10.11.12.1
        |
  private subnet   10.11.12.0/24   ← VM private IPs
        |
  lb-mgmt-net      172.16.0.0/24   ← Octavia health manager (isolated)

Terraform (remote Mac)
  ├── network workload   — public net, private net, router, security groups
  └── instances workload — keypair, security group, VM, floating IP
```

### Key networking insight

The critical configuration that makes OVN routing work on Multipass is dedicating `enp0s2` to OVS with no IP address, while keeping `enp0s1` as the untouched management interface. Devstack uses `PUBLIC_INTERFACE=enp0s2` to attach this interface to `br-ex`, giving OVN a physical path to route floating IP traffic onto the local network.

---

## Prerequisites

- Apple Silicon Mac (M1/M2/M3) with at least 16 GB RAM
- macOS 13 or later
- [Multipass](https://multipass.run) installed
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0 installed on the remote Mac
- A static route on your router: `192.168.2.0/24` via Mac Studio IP
- SSH keypair generated: `ssh-keygen -t ed25519 -f ~/.ssh/id_openstack`

---

## Multipass VM setup

Create the VM with two network interfaces — one for management, one dedicated to OVS:

```bash
multipass launch 24.04 \
  --name openstack-adm \
  --cpus 4 \
  --memory 14G \
  --disk 80G \
  --network "name=en0,mode=manual"

multipass shell openstack-adm
```

Inside the VM, verify the interfaces:

```bash
ip addr show enp0s1   # management — 192.168.2.x  (keep this untouched)
ip addr show enp0s2   # no IP — will be used by OVS
```

Prepare the system:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-openstackclient \
  openvswitch-switch openvswitch-common

sudo useradd -s /bin/bash -d /opt/stack -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
sudo chmod 0440 /etc/sudoers.d/stack
sudo usermod -aG stack www-data
sudo chmod +x /opt/stack
sudo chown -R stack:stack /opt/stack
sudo systemctl enable --now openvswitch-switch
```

---

## Devstack installation

Clone Devstack and create the configuration file:

```bash
sudo -u stack -i
git clone https://opendev.org/openstack/devstack /opt/stack/devstack
cd /opt/stack/devstack
git checkout stable/2026.1
```

Create `/opt/stack/devstack/local.conf`:

```ini
[[local|localrc]]
ADMIN_PASSWORD=secret
DATABASE_PASSWORD=secret
RABBIT_PASSWORD=secret
SERVICE_PASSWORD=secret
GIT_BASE=https://opendev.org

# Octavia OVN driver
OCTAVIA_NODE_KIND=standalone
OCTAVIA_DRIVER=ovn
OCTAVIA_AMP_IMAGE_NAME=cirros-0.6.2-aarch64-disk
OCTAVIA_AMP_FLAVOR_ID=1
OCTAVIA_MGMT_SUBNET=172.16.0.0/24
OCTAVIA_MGMT_SUBNET_START=172.16.0.2
OCTAVIA_MGMT_SUBNET_END=172.16.0.200
OCTAVIA_MGMT_PORT_IP=172.16.0.1

# Network — enp0s1 for management, enp0s2 dedicated to OVS
PUBLIC_INTERFACE=enp0s2
HOST_IP=192.168.2.14          # IP of enp0s1 — adjust to your VM
SERVICE_HOST=$HOST_IP
NO_PROXY=$HOST_IP,127.0.0.1,localhost,192.168.2.0/24,192.168.0.0/24

# OVN backend
Q_AGENT=ovn
NEUTRON_BACKEND=ovn
ML2_L3_PLUGIN=ovn-router
Q_ML2_PLUGIN_MECHANISM_DRIVERS=ovn,logger
Q_ML2_PLUGIN_TYPE_DRIVERS=local,flat,vlan,geneve
Q_ML2_TENANT_NETWORK_TYPE=geneve
OVN_BUILD_FROM_SOURCE=False
OVN_BRIDGE_MAPPINGS="public:br-ex"
OVN_L3_CREATE_PUBLIC_NETWORK=True

# Floating IP pool on local network
FLOATING_RANGE="192.168.0.0/24"
PUBLIC_NETWORK_GATEWAY="192.168.0.254"    # your router gateway
Q_FLOATING_ALLOCATION_POOL="start=192.168.0.80,end=192.168.0.89"
FIXED_RANGE="10.11.12.0/24"
NETWORK_GATEWAY="10.11.12.1"
NEUTRON_CREATE_INITIAL_NETWORKS=False

# Disabled services
disable_service tempest
disable_service swift
disable_service etcd3

# Plugins
enable_plugin neutron $GIT_BASE/openstack/neutron
enable_plugin octavia $GIT_BASE/openstack/octavia stable/2026.1
enable_plugin ovn-octavia-provider $GIT_BASE/openstack/ovn-octavia-provider
ENABLED_SERVICES+=,octavia,o-api,o-cw,o-hm,o-hk,o-da
ENABLED_SERVICES+=,ovn-octavia-provider

# ARM64 image
IMAGE_URLS="http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-aarch64-disk.img"

SERVICE_TIMEOUT=1200
LOGFILE=/opt/stack/logs/stack.sh.log
VERBOSE=True
PYTHON=/opt/stack/data/venv/bin/python3
```

Apply the required patch for OVN Python environment, then launch:

```bash
sed -i 's|\$PYTHON|/opt/stack/data/venv/bin/python3|g' \
  /opt/stack/devstack/lib/neutron_plugins/ovn_agent

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
./stack.sh 2>&1 | tee /tmp/stack.log
```

Installation takes approximately 30–45 minutes on Apple Silicon.

After installation, attach `enp0s2` to `br-ex` and make it permanent:

```bash
sudo ovs-vsctl add-port br-ex enp0s2
sudo ip link set enp0s2 up
sudo ip link set br-ex up

sudo tee /etc/systemd/system/ovs-br-ex.service << 'EOF'
[Unit]
Description=Attach enp0s2 to OVS br-ex
After=ovsdb-server.service
Wants=ovsdb-server.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
  /usr/bin/ovs-vsctl --may-exist add-port br-ex enp0s2; \
  /usr/sbin/ip link set enp0s2 up; \
  /usr/sbin/ip link set br-ex up'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now ovs-br-ex
```

---

## ARM64-specific fixes

Running OpenStack on Apple Silicon (aarch64) requires several adjustments that are not needed on x86_64.

### Nova compute — correct CPU model

Edit `/etc/nova/nova-cpu.conf` and ensure the `[libvirt]` section contains:

```ini
[libvirt]
live_migration_uri = qemu+ssh://stack@%s/system
virt_type = qemu
cpu_mode = custom
cpu_models = cortex-a57
hw_machine_type = aarch64=virt
```

The default `cortex-a15` is a 32-bit CPU model and causes `XML error: No PCI buses available` when Nova tries to spawn a VM.

```bash
sudo systemctl restart devstack@n-cpu
```

### Cloud image properties

All images must carry the correct hardware properties for ARM64:

```bash
source /opt/stack/devstack/openrc admin admin

openstack image set \
  --property hw_architecture=aarch64 \
  --property hw_machine_type=virt \
  --property hw_firmware_type=uefi \
  --property hw_disk_bus=virtio \
  --property os_type=linux \
  <image-name>
```

### Config drive — bypassing the metadata proxy

On this setup the Nova metadata proxy (HAProxy in the OVN namespace) does not correctly inject the `X-Instance-ID` header required by the metadata API. Cloud-init therefore cannot retrieve SSH keys or user-data via `169.254.169.254`.

The solution is to use a config drive, which packages all instance metadata into a virtual CD-ROM that cloud-init reads directly at boot — no network required for initialization.

In Terraform, always set:

```hcl
resource "openstack_compute_instance_v2" "web" {
  config_drive = true
  ...
}
```

---

## Terraform — network workload

The network workload creates the foundational OpenStack resources: public provider network, private tenant network, router, and security groups.

### Directory structure

```
terraform/network/
├── main.tf        — network, subnet, router, security group resources
├── variables.tf   — all configurable parameters
├── versions.tf    — provider configuration and endpoint overrides
└── outputs.tf     — resource IDs
```

### versions.tf — provider configuration

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }
  }
}

provider "openstack" {
  auth_url    = var.auth_url
  user_name   = var.user_name
  password    = var.password
  tenant_name = var.tenant_name
  domain_name = var.domain_name
  region      = var.region

  endpoint_type = "public"
  endpoint_overrides = {
    network  = "http://192.168.2.14/networking/v2.0/"
    compute  = "http://192.168.2.14/compute/v2.1/"
    identity = "http://192.168.2.14/identity/v3/"
    image    = "http://192.168.2.14/image/v2/"
    volume   = "http://192.168.2.14/volume/v3/"
  }
}
```

### main.tf — key resources

```hcl
# Public provider network (flat, mapped to br-ex)
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

# Private tenant network
resource "openstack_networking_network_v2" "private" {
  name           = var.private_network_name
  admin_state_up = true
  shared         = false
}

# Router connecting private to public
resource "openstack_networking_router_v2" "router1" {
  name                = var.router_name
  admin_state_up      = true
  external_network_id = openstack_networking_network_v2.public.id
}
```

### Deploy

```bash
cd terraform/network
terraform init
terraform apply
```

---

## Terraform — instances workload

The instances workload deploys a web server VM with a floating IP.

### Directory structure

```
terraform/instances/
├── instance.tf    — keypair, security group, VM, floating IP
├── variables.tf   — image, flavor, SSH key path, password
├── versions.tf    — same provider configuration as network workload
└── outputs.tf     — floating IP, SSH command, web URL
```

### instance.tf — key configuration

```hcl
resource "openstack_compute_instance_v2" "web" {
  name            = var.instance_name
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = openstack_compute_keypair_v2.mykey.name
  security_groups = [openstack_networking_secgroup_v2.web.name]
  config_drive    = true    # required — bypasses broken metadata proxy

  network {
    uuid = data.openstack_networking_network_v2.private.id
  }

  user_data = <<-EOF
    #cloud-config
    password: ${var.instance_password}
    chpasswd:
      expire: false
    ssh_pwauth: true
    packages:
      - nginx
    runcmd:
      - systemctl enable --now nginx
  EOF
}
```

### Deploy

```bash
cd terraform/instances
terraform init
terraform apply
```

After deployment, the outputs show:

```
floating_ip = "192.168.0.8x"
web_url     = "http://192.168.0.8x"
ssh_command = "ssh cloud-user@192.168.0.8x"
```

Connect:

```bash
ssh -i ~/.ssh/id_openstack cloud-user@192.168.0.8x
curl http://192.168.0.8x
```

---

## Known issues and fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| `No PCI buses available` | Nova uses `cortex-a15` (32-bit) CPU | Set `cpu_models = cortex-a57` in `nova-cpu.conf` |
| `ModuleNotFoundError: No module named 'neutron'` | OVN agent uses system Python | Patch `$PYTHON` → venv path in `ovn_agent` |
| `br-ex` empty after install | Devstack cannot attach interface it doesn't own | Manually attach `enp0s2` + create systemd service |
| Cloud-init no SSH key | Metadata proxy returns 400 (missing `X-Instance-ID`) | Use `config_drive = true` in Terraform |
| VM boots but no network | `hw_disk_bus` not set on image | Add `--property hw_disk_bus=virtio` to image |
| `octavia-dashboard` crash | Incompatible with this Devstack version | Remove from `local.conf` |

---

## Conclusion

This project demonstrates that a fully operational OpenStack cloud — with compute, networking, load balancing, and infrastructure-as-code deployment — can run on a single Apple Silicon Mac. The combination of Multipass for lightweight ARM64 virtualization, Devstack for rapid OpenStack deployment, OVN for high-performance software-defined networking, and Terraform for repeatable infrastructure provisioning creates a powerful local lab environment.

The most significant challenges encountered were specific to the ARM64 architecture on Apple Silicon: the QEMU CPU model mismatch (`cortex-a15` vs `cortex-a57`), the OVN metadata proxy not forwarding instance identity headers correctly, and the OVS bridge requiring manual physical interface attachment.

Each of these issues has a documented fix in this guide. The resulting environment faithfully mirrors the workflow of a production OpenStack deployment — provision networks and instances with Terraform, connect via SSH using injected keys, expose services through floating IPs — making it an effective platform for learning, testing Terraform modules, validating cloud-init configurations, and exploring OpenStack APIs before deploying to production infrastructure.

---

## Repository structure

```
.
├── README.md
├── terraform/
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── versions.tf
│   │   └── outputs.tf
│   └── instances/
│       ├── instance.tf
│       ├── variables.tf
│       ├── versions.tf
│       └── outputs.tf
└── devstack/
    └── local.conf.example
```

---

*Built with OpenStack 2026.1 · Devstack · OVN · Terraform · Multipass · Apple Silicon*
