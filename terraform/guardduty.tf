resource "aws_guardduty_detector" "this" {
  enable = true
}

resource "aws_sns_topic" "guardduty_findings" {
  name         = "GD-AlarmNotificationTopic"
  display_name = "GD-AlarmNotificationTopic"
}

resource "aws_sns_topic_subscription" "guardduty_findings_email" {
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "email"
  endpoint  = var.guardduty_notification_email
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "GD-Findings"
  description = "Send GuardDuty findings to email"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })

  depends_on = [aws_guardduty_detector.this]
}

resource "aws_cloudwatch_event_target" "guardduty_findings" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GDAlerts"
  arn       = aws_sns_topic.guardduty_findings.arn

  depends_on = [aws_sns_topic_policy.guardduty_findings]

  input_transformer {
    input_paths = {
      account_id   = "$.detail.accountId"
      description  = "$.detail.description"
      finding_id   = "$.detail.id"
      finding_type = "$.detail.type"
      region       = "$.region"
      severity     = "$.detail.severity"
    }

    input_template = jsonencode({
      message     = "AWS <account_id> has a severity <severity> GuardDuty finding of type <finding_type> in the <region> region."
      description = "<description>"
      console_url = "https://console.aws.amazon.com/guardduty/home?region=<region>#/findings?search=id=<finding_id>"
    })
  }
}

data "aws_iam_policy_document" "guardduty_findings_topic" {
  statement {
    sid    = "AllowEventBridgeToPublishGuardDutyFindings"
    effect = "Allow"

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.guardduty_findings.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.guardduty_findings.arn]
    }
  }
}

resource "aws_sns_topic_policy" "guardduty_findings" {
  arn    = aws_sns_topic.guardduty_findings.arn
  policy = data.aws_iam_policy_document.guardduty_findings_topic.json
}
