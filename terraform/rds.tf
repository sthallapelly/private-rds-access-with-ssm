resource "aws_db_subnet_group" "database" {
  name       = "${var.project_name}-db"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.project_name}-db" }
}
resource "aws_db_instance" "database" {
  identifier                 = var.project_name
  engine                     = "mysql"
  engine_version             = var.rds_engine_version
  engine_lifecycle_support   = "open-source-rds-extended-support-disabled"
  instance_class             = var.rds_instance_class
  allocated_storage          = var.rds_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.database_name
  username                   = var.database_username
  password                   = var.database_password
  port                       = 3306
  db_subnet_group_name       = aws_db_subnet_group.database.name
  vpc_security_group_ids     = [aws_security_group.database.id]
  publicly_accessible        = false
  multi_az                   = var.rds_multi_az
  availability_zone          = var.rds_multi_az ? null : aws_subnet.private[0].availability_zone
  backup_retention_period    = var.rds_backup_retention_period
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  # LAB ONLY: disposable data, immediate changes and straightforward teardown.
  deletion_protection          = false
  skip_final_snapshot          = true
  delete_automated_backups     = true
  apply_immediately            = true
  performance_insights_enabled = false
  tags                         = { Name = "${var.project_name}-db" }
}
