variable "aws_region" {
  description = "AWS region for infrastructure resources."
  type        = string
}

variable "aws_acct_num" {
  description = "AWS account ID used in account-scoped resource names and policies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_acct_num))
    error_message = "The AWS account ID must contain exactly 12 digits."
  }
}

variable "guardduty_notification_email" {
  description = "Email address that receives GuardDuty finding notifications."
  type        = string
}
