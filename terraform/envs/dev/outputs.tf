output "alb_url" {
  description = "Public URL for the service."
  value       = "http://${module.alb.alb_dns_name}"
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "dashboard_name" {
  value = module.observability.dashboard_name
}

output "github_actions_role_arn" {
  description = "Set this as AWS_ROLE_TO_ASSUME secret in GitHub Actions."
  value       = aws_iam_role.gha_deployer.arn
}
