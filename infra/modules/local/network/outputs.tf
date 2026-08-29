output "name" {
  description = "Docker network name."
  value       = docker_network.this.name
}

output "id" {
  description = "Docker network id."
  value       = docker_network.this.id
}
