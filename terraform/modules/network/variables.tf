variable "name" {
  description = "Name prefix applied to all network resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "tags" {
  description = "Tags applied to all network resources."
  type        = map(string)
  default     = {}
}
