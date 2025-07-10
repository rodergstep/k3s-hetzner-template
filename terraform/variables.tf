variable "worker_node_pools" {
  description = "A list of worker node pools to create."
  type = list(object({
    name           = string
    instance_type  = string
    instance_count = number
    location       = string
  }))
}