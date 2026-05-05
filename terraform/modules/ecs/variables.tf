variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "image" {
  description = "Full image URI including tag (e.g. <acct>.dkr.ecr.<region>.amazonaws.com/repo:sha)."
  type        = string
}

variable "container_name" {
  type    = string
  default = "app"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 4
}

variable "app_version" {
  type    = string
  default = "dev"
}

variable "git_sha" {
  type    = string
  default = "unknown"
}

variable "tags" {
  type    = map(string)
  default = {}
}
