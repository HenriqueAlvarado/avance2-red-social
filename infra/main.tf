terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Data sources ─────────────────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── S3 Bucket (privado y cifrado) ────────────────────────────────────────────
resource "aws_s3_bucket" "media" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Project     = "avance2-red-social"
    Environment = "qa"
  }
}

# Bloquear todo acceso público
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cifrado del bucket con SSE-S3
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versionado habilitado
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ── Security Group para RDS ───────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "avance2-rds-sg"
  description = "Acceso a RDS solo desde la instancia EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "PostgreSQL desde EC2"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.ec2_private_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "avance2-red-social"
  }
}

# ── Subnet Group para RDS ─────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "avance2-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Project = "avance2-red-social"
  }
}

# ── RDS PostgreSQL (cifrada, sin acceso público) ──────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier        = "avance2-redsocial-db"
  engine            = "postgres"
  engine_version    = "16.9"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  # Seguridad obligatoria
  publicly_accessible    = false
  storage_encrypted      = true
  deletion_protection    = false
  skip_final_snapshot    = true
  multi_az               = false

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = {
    Project     = "avance2-red-social"
    Environment = "qa"
  }
}
