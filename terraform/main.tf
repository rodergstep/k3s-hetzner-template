provider "hcloud" {
  token = var.hcloud_token
}

# Create a private network for the k3s cluster
resource "hcloud_network" "private_network" {
  name     = "k3s-network"
  ip_range = "10.0.0.0/16"
}

# Create a subnet for the private network
resource "hcloud_network_subnet" "private_subnet" {
  network_id   = hcloud_network.private_network.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# Create a firewall to protect the k3s cluster
resource "hcloud_firewall" "k3s_firewall" {
  name = "k3s-firewall"

  # Allow SSH access from your IP address
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "${var.local_ip}/32"
    ]
  }

  # Allow Kubernetes API server access only from the private network and your IP
  # This is a critical security improvement.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      hcloud_network.private_network.ip_range,
      "${var.local_ip}/32"
    ]
  }

  # Allow flannel VXLAN traffic only between nodes in the private network
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "8472"
    source_ips = [
      hcloud_network.private_network.ip_range
    ]
  }
}

# Create the k3s master node
resource "hcloud_server" "master" {
  name        = "k3s-master"
  server_type = var.master_server_type
  image       = "ubuntu-22.04"
  location    = var.region
  ssh_keys    = [hcloud_ssh_key.default.name]
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.100"
  }
  firewall_ids = [hcloud_firewall.k3s_firewall.id]
}

# Create a placement group for the worker nodes to ensure they are spread across different hosts
resource "hcloud_placement_group" "worker_placement_group" {
  name = "worker-placement-group"
  type = "spread"
}

# Create k3s worker nodes
resource "hcloud_server" "worker" {
  for_each = { for pool in var.worker_node_pools : pool.name => pool }

  name        = "k3s-worker-${each.key}-${count.index}"
  server_type = each.value.instance_type
  image       = "ubuntu-22.04"
  location    = each.value.location
  count       = each.value.instance_count

  labels = {
    "pool" = each.key
  }

  ssh_keys    = [hcloud_ssh_key.default.name]
  placement_group_id = hcloud_placement_group.worker_placement_group.id
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.${101 + count.index}"
  }
  firewall_ids = [hcloud_firewall.k3s_firewall.id]
}

# Attach the master node to the private network
resource "hcloud_server_network" "master_network" {
  server_id  = hcloud_server.master.id
  network_id = hcloud_network.private_network.id
  ip         = hcloud_server.master.network[0].ip
}

# Create an SSH key to access the servers
resource "hcloud_ssh_key" "default" {
  name       = var.ssh_key_name
  public_key = file(var.ssh_public_key_path)
}
