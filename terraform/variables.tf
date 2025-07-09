variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Hetzner Cloud region"
  type        = string
  default     = "nbg1"
}

variable "master_server_type" {
  description = "Server type for the k3s master node"
  type        = string
  default     = "cpx11" # Upgraded for more stability
}

variable "worker_server_type" {
  description = "Server type for the k3s worker nodes"
  type        = string
  default     = "cpx31" # Upgraded to handle production workload
}

variable "ssh_key_name" {
  description = "Name of the SSH key to use for the servers"
  type        = string
}
