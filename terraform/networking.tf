resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.project_name }
}

# Two shared private subnets suffice: SGs establish the trust boundaries.
# Endpoints and the managed node use subnet 0 to minimize endpoint/AZ charges.
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-private-${count.index + 1}" }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
  # Only the implicit VPC local route: no IGW, NAT, IPv6 or default route.
  tags = { Name = "${var.project_name}-private" }
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
