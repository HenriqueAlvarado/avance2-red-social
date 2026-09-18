output "s3_bucket_name" {
  description = "Nombre del bucket S3"
  value       = aws_s3_bucket.media.bucket
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos RDS"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_db_name" {
  description = "Nombre de la base de datos"
  value       = aws_db_instance.postgres.db_name
}
