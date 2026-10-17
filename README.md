# aws-infra

Terraform infrastructure for AWS.

Before enabling deployment, configure these repository secrets:

- `AWS_ACCT_NUM`: AWS account ID used to construct the Terraform state bucket
  name.
- `AWS_REGION`: AWS region for the managed infrastructure.
- `AWS_ROLE_ARN`: IAM role ARN assumed by GitHub Actions through OIDC.
- `GD_NOTIFICATION_EMAIL_ADDRESS`: address subscribed to GuardDuty finding
  notifications. Confirm the SNS subscription from the email AWS sends after
  deployment.
