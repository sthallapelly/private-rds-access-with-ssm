data "aws_caller_identity" "flow" {
  count = var.enable_flow_logs ? 1 : 0
}

resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/${var.project_name}/vpc-flow"
  retention_in_days = 3
}
data "aws_iam_policy_document" "flow_trust" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.flow[0].account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.flow[0].account_id}:vpc-flow-log/*"]
    }
  }
}
resource "aws_iam_role" "flow" {
  count              = var.enable_flow_logs ? 1 : 0
  name_prefix        = "${var.project_name}-flow-"
  assume_role_policy = data.aws_iam_policy_document.flow_trust[0].json
}
data "aws_iam_policy_document" "flow" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = [aws_cloudwatch_log_group.flow[0].arn, "${aws_cloudwatch_log_group.flow[0].arn}:*"]
  }
  statement {
    # This discovery action does not support resource-level permissions.
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "flow" {
  count  = var.enable_flow_logs ? 1 : 0
  name   = "write-flow-logs"
  role   = aws_iam_role.flow[0].id
  policy = data.aws_iam_policy_document.flow[0].json
}
resource "aws_flow_log" "lab" {
  count                    = var.enable_flow_logs ? 1 : 0
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn             = aws_iam_role.flow[0].arn
  max_aggregation_interval = 60
  depends_on               = [aws_iam_role_policy.flow]
}
