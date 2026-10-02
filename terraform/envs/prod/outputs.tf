output "service_url" {
  description = "URL publica del servicio (usada por el smoke test del pipeline)."
  value       = module.app.service_url
}

output "cluster_name" {
  description = "Cluster ECS."
  value       = module.app.cluster_name
}

output "service_name" {
  description = "Servicio ECS."
  value       = module.app.service_name
}
