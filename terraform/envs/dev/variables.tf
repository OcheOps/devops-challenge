variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "name" {
  description = "Name prefix for all resources in this environment."
  type        = string
  default     = "devops-challenge-dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

# Image to deploy. On the very first apply (before CI has pushed an image),
# point this at a public placeholder so ECS can start. CD updates the
# task definition out-of-band on every merge to main.
variable "image" {
  description = "Full image URI (repo:tag). Default is a tiny placeholder for first-time apply."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable-alpine"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "github_repository" {
  description = "owner/repo — used to scope the GitHub OIDC trust policy."
  type        = string
}
