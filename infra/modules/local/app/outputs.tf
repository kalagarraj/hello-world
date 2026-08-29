output "container_name" {
  description = "Name of the running container."
  value       = docker_container.this.name
}

output "url" {
  description = "Host URL when the app publishes a port, otherwise null."
  value       = var.spec.host_port == null ? null : "http://localhost:${var.spec.host_port}"
}

output "internal_target" {
  description = "host:port other containers use to reach this app."
  value       = "${var.name}:${var.spec.port}"
}
