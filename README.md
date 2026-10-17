# aws-infra

Terraform infrastructure for AWS.

## Local development

Open the repository in the dev container to use Terraform, the AWS CLI, and
GitHub CLI. Authenticate the AWS CLI with your preferred local credentials
before running Terraform commands.

From the repository root:

```sh
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

Use `terraform init` with the same S3 backend settings as the deployment workflow
when working against shared state.

## GitHub Actions deployment setup

Pull requests run Terraform formatting, initialization, and validation without
AWS credentials. Merges to `main` run `terraform plan` and apply the resulting
plan using GitHub Actions OIDC.

Before enabling deployment, configure these repository secrets:

- `AWS_ACCT_NUM`: AWS account ID used to construct the Terraform state bucket
  name.
- `AWS_REGION`: AWS region for the managed infrastructure.
- `AWS_ROLE_ARN`: IAM role ARN assumed by GitHub Actions through OIDC.
- `GD_NOTIFICATION_EMAIL_ADDRESS`: address subscribed to GuardDuty finding
  notifications. Confirm the SNS subscription from the email AWS sends after
  deployment.

Terraform state is stored in the pre-created, versioned
`terraform-state-${AWS_ACCT_NUM}-us-east-1-an` bucket in `us-east-1`. The
deployment workflow assumes the role configured by `AWS_ROLE_ARN` using GitHub
Actions OIDC. Its trust policy must allow the GitHub OIDC provider
(`token.actions.githubusercontent.com`), audience `sts.amazonaws.com`, and
subject `repo:tkhom3/aws-infra:ref:refs/heads/main`. Grant the role access to the
state object and only the AWS resources managed by this repository. Update the
trust policy and permissions as infrastructure is added.

The state bucket restriction policy is in
[`terraform/state_bucket_policy.json`](./terraform/state_bucket_policy.json). It
allows the deploy role access only to the Terraform state and lock objects,
allows the specified IAM Identity Center AdministratorAccess role full bucket
access only for the `ToddMKieffer` role session, and explicitly denies all other
principals and sessions using that permission set. Apply it while authenticated
as that Identity Center user:

```sh
aws s3api put-bucket-policy \
  --bucket "terraform-state-${AWS_ACCT_NUM}-us-east-1-an" \
  --policy file://terraform/state_bucket_policy.json
```

The policy handles both possible IAM Identity Center role ARN paths for an
instance in `us-east-1` versus another home region, and checks the `ToddMKieffer`
role session name because the role ARN itself is shared by users assigned to
that permission set. This is a strict restriction: the account root and all
other users, roles, and AWS services are denied access to the state bucket.
Keep access to the named Identity Center user so the policy can be repaired if
needed.

## GuardDuty findings

Terraform enables the GuardDuty detector in `AWS_REGION` and provisions the
SNS email topic and EventBridge rule from the former
`tkhom3/aws-deploy-gd-notifications` CloudFormation template. Confirm the SNS
subscription email to start receiving findings.

Only GuardDuty's foundational detection is enabled. Optional protection plans
that can add charges (such as S3, EKS, malware, RDS, and runtime monitoring) are
left disabled; GuardDuty usage itself may incur charges after any applicable
free trial.

## CloudTrail logs

Terraform manages the multi-region `ct-logs` trail and its
`${AWS_ACCT_NUM}-cloudtrail-logs` S3 bucket. The trail records management events
and S3 object data events, excluding KMS management events. The bucket enforces
AES256 encryption, blocks public access, and expires log objects after 180
days; applying lifecycle changes can permanently delete log data. The bucket's
existing SSE-C blocking setting is not exposed by the current AWS provider
schema and remains outside Terraform management.

## Existing backup bucket

Terraform configuration for the existing `tkhom3-home-lab-backup` bucket is in
[`terraform/backup_bucket.tf`](./terraform/backup_bucket.tf). It manages the
bucket policy, AES256 default encryption, enabled versioning, and the lifecycle
rule shown in the AWS console (expire noncurrent versions after 30 days, remove
expired delete markers, and abort incomplete multipart uploads after 7 days).
The `unraid_backup/` prefix retains that 30-day noncurrent-version expiration.
The `photos/` prefix instead retains deleted object versions for 60 days before
permanently expiring them. Current photo objects are not expired based on age;
the 60-day clock starts when `s3cmd sync --delete` makes a version noncurrent.
Expired delete markers are cleaned up and incomplete multipart uploads are
aborted after 7 days across the bucket.

First configure AWS credentials for the account in `AWS_ACCT_NUM` with
permission to read and manage the bucket, then configure the backend. For
example:

```sh
export AWS_ACCT_NUM="$(aws sts get-caller-identity --query Account --output text)"
export TF_VAR_aws_region=us-east-1
export TF_VAR_aws_acct_num="$AWS_ACCT_NUM"
export TF_VAR_guardduty_notification_email=your-notification-address@example.com
terraform -chdir=terraform init \
  -backend-config="bucket=terraform-state-${AWS_ACCT_NUM}-us-east-1-an" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"
```

Import the bucket and its separately managed settings into the same Terraform
state:

```sh
terraform import aws_s3_bucket.home_lab_backup tkhom3-home-lab-backup
terraform import aws_s3_bucket_versioning.home_lab_backup tkhom3-home-lab-backup
terraform import aws_s3_bucket_lifecycle_configuration.home_lab_backup tkhom3-home-lab-backup
terraform import aws_s3_bucket_server_side_encryption_configuration.home_lab_backup tkhom3-home-lab-backup
terraform import aws_s3_bucket_policy.home_lab_backup tkhom3-home-lab-backup
```

Imports only associate existing AWS objects with Terraform state; they do not
apply the configuration. After importing, run `terraform plan` and review every
proposed change before applying. In particular, applying the lifecycle policy
permanently deletes noncurrent object versions after 30 days, as the existing
console rule indicates. If the bucket's actual policy or settings differ from
the supplied policy and screenshots, update the configuration to match the
intended live behavior before applying.