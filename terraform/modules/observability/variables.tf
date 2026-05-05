variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group consumed by the dashboard widget."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
