variable "aws_region" {
  description = "Sandbox-approved AWS Region with at least two available AZs."
  type        = string
  default     = "us-east-2"
}
variable "project_name" {
  description = "Short resource prefix; use a unique value per lab in an account."
  type        = string
  default     = "private-rds-ssm"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.project_name)) && !endswith(var.project_name, "-") && !strcontains(var.project_name, "--")
    error_message = "Use 3–30 lowercase letters, digits or hyphens, starting with a letter, without trailing or consecutive hyphens."
  }
}
variable "vpc_cidr" {
  description = "Dedicated IPv4 VPC CIDR."
  type        = string
  default     = "10.42.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "Provide a valid IPv4 CIDR."
  }
}
variable "private_subnet_cidrs" {
  description = "Exactly two non-overlapping IPv4 subnet CIDRs inside the VPC; one per AZ."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]
  validation {
    condition     = length(var.private_subnet_cidrs) == 2 && length(distinct(var.private_subnet_cidrs)) == 2 && alltrue([for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply two distinct valid IPv4 subnet CIDRs. Review containment and overlap before planning."
  }
}
variable "ec2_instance_type" {
  description = "Small x86_64 instance type allowed in your sandbox."
  type        = string
  default     = "t3.micro"
}
variable "ami_id" {
  description = "Optional approved x86_64 Amazon Linux 2023 AMI with SSM Agent >= 3.3.40.0; null discovers latest. Pin for repeatability."
  type        = string
  default     = null
}
variable "rds_instance_class" {
  description = "Sandbox-approved RDS MySQL class."
  type        = string
  default     = "db.t3.micro"
}
variable "rds_engine_version" {
  description = "MySQL major/minor version available for the chosen class/Region. Pin a full version for repeatability."
  type        = string
  default     = "8.4"
}
variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "labdb"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,63}$", var.database_name))
    error_message = "Use 1–64 alphanumeric characters, starting with a letter."
  }
}
variable "database_username" {
  description = "RDS master username for this temporary lab; avoid reserved engine usernames."
  type        = string
  default     = "labadmin"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,15}$", var.database_username))
    error_message = "Use 1–16 alphanumeric characters, starting with a letter."
  }
}
variable "database_password" {
  description = "Supply privately. Sensitive redacts CLI output but this value IS stored in local state and saved plans."
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition     = length(var.database_password) >= 8 && length(var.database_password) <= 41 && can(regex("^[!-~]+$", var.database_password)) && !can(regex("[/@\" ]", var.database_password))
    error_message = "Use 8–41 printable ASCII characters excluding slash, at sign, double quote and spaces."
  }
}
variable "rds_allocated_storage" {
  description = "Initial gp3 storage in GiB; no storage autoscaling in this lab."
  type        = number
  default     = 20
  validation {
    condition     = var.rds_allocated_storage >= 20 && floor(var.rds_allocated_storage) == var.rds_allocated_storage
    error_message = "Use an integer of at least 20 GiB."
  }
}
variable "rds_multi_az" {
  description = "LAB default false; true adds cost. Subnet group always spans two AZs."
  type        = bool
  default     = false
}
variable "rds_backup_retention_period" {
  description = "LAB default disables automated backups; 0–35 days."
  type        = number
  default     = 0
  validation {
    condition     = var.rds_backup_retention_period >= 0 && var.rds_backup_retention_period <= 35 && floor(var.rds_backup_retention_period) == var.rds_backup_retention_period
    error_message = "Retention must be an integer from 0 to 35."
  }
}
variable "enable_flow_logs" {
  description = "Optional VPC traffic metadata in CloudWatch Logs; adds IAM and logging cost."
  type        = bool
  default     = false
}
