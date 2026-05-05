variable "name" {
  description = "ECR repository name."
  type        = string
}

variable "force_delete" {
  description = "Allow `terraform destroy` to remove the repo even if it contains images. Useful for ephemeral envs."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
