variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Nombre del bucket S3 (debe ser único globalmente)"
  type        = string
  default     = "avance2-redsocial-media-henrique"
}

variable "ec2_private_cidr" {
  description = "CIDR privado de la instancia EC2 para acceso a RDS"
  type        = string
  default     = "172.31.17.200/32"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "redsocial"
}

variable "db_user" {
  description = "Usuario de la base de datos"
  type        = string
  default     = "adminrs"
}

variable "db_password" {
  description = "Contraseña de la base de datos (usa terraform.tfvars, no hardcodees)"
  type        = string
  sensitive   = true
}
