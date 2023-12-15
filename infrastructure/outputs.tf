output "api_url" {
  description = "Base URL for API Gateway stage."
  value       = aws_apigatewayv2_stage.lambda.invoke_url
}

output "distribution_domain" {
  description = "CloudFront distribution domain."
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
}
