resource "aws_security_group" "node" {
  name_prefix = "${var.project_name}-node-"
  description = "SSM managed node; no inbound rules"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.project_name}-node" }
}
resource "aws_security_group" "endpoints" {
  name_prefix = "${var.project_name}-vpce-"
  description = "SSM interface endpoints; HTTPS from managed node only"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.project_name}-vpce" }
}
resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-db-"
  description = "MySQL from managed node only"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.project_name}-db" }
}
resource "aws_vpc_security_group_egress_rule" "node_https" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Agent HTTPS to SSM endpoint ENIs"
}
resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from SSM node"
}
resource "aws_vpc_security_group_egress_rule" "node_mysql" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL to RDS"
}
resource "aws_vpc_security_group_ingress_rule" "database_mysql" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL from SSM node"
}
# SGs are stateful: DB/endpoint response packets need no outbound rules.
# AmazonProvidedDNS is not filtered by SGs; no redundant port 53 rule.
