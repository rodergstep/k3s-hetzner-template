variable "worker_node_pools" {
  description = "A list of worker node pools to create."
  type = list(object({
    name           = string
    instance_type  = string
    instance_count = number
    location       = string
  }))
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token."
  type        = string
  sensitive   = true
}

variable "master_server_type" {
  description = "The server type for the master node."
  type        = string
}

variable "region" {
  description = "The region to deploy the cluster in."
  type        = string
}

variable "ssh_key_name" {
  description = "The name of the SSH key to use."
  type        = string
}

variable "ssh_public_key_path" {
  description = "The path to the public SSH key."
  type        = string
}

variable "local_ip_for_ssh" {
  description = "Your local IP address for SSH access."
  type        = string
}