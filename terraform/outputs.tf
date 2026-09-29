output "aws_region" { value = var.aws_region }
output "vpc_id" { value = aws_vpc.lab.id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "private_route_table_id" { value = aws_route_table.private.id }
output "ec2_instance_id" { value = aws_instance.node.id }
output "ec2_private_ip" { value = aws_instance.node.private_ip }
output "ec2_ami_id" { value = aws_instance.node.ami }
output "ec2_security_group_id" { value = aws_security_group.node.id }
output "rds_identifier" { value = aws_db_instance.database.identifier }
output "rds_endpoint" { value = aws_db_instance.database.address }
output "rds_port" { value = aws_db_instance.database.port }
output "rds_security_group_id" { value = aws_security_group.database.id }
output "endpoint_security_group_id" { value = aws_security_group.endpoints.id }
output "ssm_vpc_endpoint_ids" {
  value = { for service, endpoint in aws_vpc_endpoint.ssm : service => endpoint.id }
}
output "endpoint_dns_entries" {
  value = { for service, endpoint in aws_vpc_endpoint.ssm : service => endpoint.dns_entry }
}
output "endpoint_network_interface_ids" {
  value = { for service, endpoint in aws_vpc_endpoint.ssm : service => endpoint.network_interface_ids }
}
output "ssm_service_hostnames" {
  value = { for service in local.ssm_services : service => "${service}.${var.aws_region}.${data.aws_partition.current.dns_suffix}" }
}
output "flow_log_group_name" {
  value = try(aws_cloudwatch_log_group.flow[0].name, null)
}
