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

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "local_ip" {
  description = "Your local IP address to allow access to the cluster"
  type        = string
}
