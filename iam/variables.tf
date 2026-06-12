
variable "aws_region" {
  type = string
  validation {
    condition     = can(regex("[a-z][a-z]-[a-z]+-[1-9]", var.aws_region))
    error_message = "Invalid AWS Region name."
  }
}

variable "aws_account_id" {
  type = string
  validation {
    condition     = length(var.aws_account_id) == 12 && can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "Invalid AWS account ID"
  }
}

variable "aws_assume_role" { type = string }

variable "is_state_account" {
  description = "create STATE account configuration?"
  type        = bool
  default     = false
}

variable "target_account_ids" {
  description = "AWS account IDs that the deployment role may assume into"
  type        = list(string)
  default     = []
}

variable "app_env" {
  description = "Short environment name used in resource naming (e.g. dev, sbx, qa, prod)"
  type        = string
}
