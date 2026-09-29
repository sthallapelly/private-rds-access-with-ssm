locals {
  # Modern SSM Agent (>= 3.3.40.0) uses ssmmessages. ec2messages is legacy
  # and unavailable in Regions launched in 2024 or later. See README sources.
  ssm_services = toset(["ssm", "ssmmessages"])
}
resource "aws_vpc_endpoint" "ssm" {
  for_each            = local.ssm_services
  vpc_id              = aws_vpc.lab.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.endpoints.id]
  # Default endpoint policy; IAM authorization and SGs are distinct controls.
  tags = { Name = "${var.project_name}-${each.key}" }
}
