variable "name" {
  description = "Name of the docker bridge network."
  type        = string
}

variable "subnet" {
  description = "CIDR block assigned to the bridge network."
  type        = string
  default     = "172.28.0.0/16"
}
