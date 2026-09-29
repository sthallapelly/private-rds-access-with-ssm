data "aws_ssm_parameter" "amazon_linux" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_instance" "node" {
  ami                         = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.amazon_linux[0].value)
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.private[0].id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.node.id]
  iam_instance_profile        = aws_iam_instance_profile.node.name
  monitoring                  = false
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }
  # No downloads or package updates: bootstrap must work with no internet route.
  user_data                   = <<-EOT
    #!/bin/bash
    set -euo pipefail
    systemctl enable --now amazon-ssm-agent
  EOT
  user_data_replace_on_change = true
  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_endpoint.ssm,
    aws_route_table_association.private
  ]
  tags = { Name = "${var.project_name}-node" }
}
