provider "aws" {
  region = var.aws_region
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "weather-station"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id
}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_bucket]
  bucket     = aws_s3_bucket.lambda_bucket.id
  acl        = "private"
}

data "archive_file" "db_query_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/${var.db_query_lambda_name}"
  output_path = "${path.module}/packed_lambdas/${var.db_query_lambda_name}.zip"
}

resource "aws_s3_object" "db_query_lambda" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "${var.db_query_lambda_name}.zip"
  source = data.archive_file.db_query_lambda.output_path
  etag   = filemd5(data.archive_file.db_query_lambda.output_path)
}

resource "aws_lambda_function" "db_query_lambda" {
  function_name    = "DBQuery"
  s3_bucket        = aws_s3_bucket.lambda_bucket.id
  s3_key           = aws_s3_object.db_query_lambda.key
  runtime          = "python3.11"
  handler          = "main.handler"
  source_code_hash = data.archive_file.db_query_lambda.output_base64sha256
  role             = aws_iam_role.lambda_execution.arn
}

resource "aws_cloudwatch_log_group" "db_query_lambda" {
  name = "/aws/lambda/${aws_lambda_function.db_query_lambda.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_execution" {
  name = "LambdaExecution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# API Gateway to lambda functions

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gateway"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "db_query_lambda" {
  api_id             = aws_apigatewayv2_api.lambda.id
  integration_uri    = aws_lambda_function.db_query_lambda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "db_query_lambda" {
  api_id    = aws_apigatewayv2_api.lambda.id
  route_key = "GET /weather_data"
  target    = "integrations/${aws_apigatewayv2_integration.db_query_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/api_gateway/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_query_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

# IoT data recieving lambda, which will write data to DynamoDB

data "archive_file" "data_receiving_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/data_receiving_lambda"
  output_path = "${path.module}/packed_lambdas/data_receiving_lambda.zip"
}

resource "aws_s3_object" "data_recieving_lambda" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "data_receiving_lambda.zip"
  source = data.archive_file.data_receiving_lambda.output_path
  etag   = filemd5(data.archive_file.data_receiving_lambda.output_path)
}

resource "aws_lambda_function" "data_recieving_lambda" {
  function_name    = "DataReciever"
  s3_bucket        = aws_s3_bucket.lambda_bucket.id
  s3_key           = aws_s3_object.data_recieving_lambda.key
  runtime          = "python3.11"
  handler          = "main.handler"
  source_code_hash = data.archive_file.data_receiving_lambda.output_base64sha256
  role             = aws_iam_role.lambda_execution.arn
}

resource "aws_cloudwatch_log_group" "data_recieving_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.data_recieving_lambda.function_name}"
  retention_in_days = 30
}

# Rule for iot topic to trigger lambda
resource "aws_iot_topic_rule" "pass_data_to_data_reciever" {
  name        = "PassDataToDataReciever"
  enabled     = true
  sql         = "SELECT * FROM 'weather-station/data'"
  sql_version = "2016-03-23"
  lambda {
    function_arn = aws_lambda_function.data_recieving_lambda.arn
  }
}

# Allow triggering data_receiving_lambda from IoT Core Rule
resource "aws_lambda_permission" "allow_data_recieving_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_recieving_lambda.function_name
  principal     = "iot.amazonaws.com"
}

# DynamoDB table for storing weather data
resource "aws_dynamodb_table" "weather_data" {
  name         = "WeatherData"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "DeviceId"
  range_key    = "Timestamp"

  attribute {
    name = "DeviceId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "N"
  }

  attribute {
    name = "Temperature"
    type = "N"
  }

  attribute {
    name = "Humidity"
    type = "N"
  }

  global_secondary_index {
    name               = "WeatherDataIndex"
    hash_key           = "Temperature"
    range_key          = "Humidity"
    write_capacity     = 10
    read_capacity      = 10
    projection_type    = "INCLUDE"
    non_key_attributes = ["Temperature", "Humidity"]
  }
}

# IAM policy allowing operations with DynamoDB table weather_station
resource "aws_iam_policy" "weather_data_access" {
  name = "WeatherDataAccess"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [{
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:PartiQLSelect"
        ],
        "Resource" : "${aws_dynamodb_table.weather_data.arn}"
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource" : "${aws_dynamodb_table.weather_data.arn}:*"
        },
        {
          "Effect" : "Allow",
          "Action" : "logs:CreateLogGroup",
          "Resource" : "*"
        }
      ]
    }
  )
}

# Attaching IAM policy to lambda execution role
resource "aws_iam_role_policy_attachment" "allow_access_to_weather_data" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.weather_data_access.arn
}

# Building react application
data "external" "frontend_build" {
  program = ["bash", "-c", <<EOT
REACT_APP_API_URL=$(jq -r '.api_url') npm run build  >&2 && echo "{\"dest\": \"build\"}"
EOT
  ]
  working_dir = "${path.module}/../react-app"
  query = {
    api_url = aws_apigatewayv2_stage.lambda.invoke_url
  }
}

# Uploading react application to S3 bucket


resource "random_pet" "react_bucket_name" {
  prefix = "weather-station-react"
  length = 4
}

resource "aws_s3_bucket" "react_bucket" {
  bucket = random_pet.react_bucket_name.id
}

resource "aws_s3_bucket_ownership_controls" "react_bucket" {
  bucket = aws_s3_bucket.react_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "react_bucket" {
  bucket = aws_s3_bucket.react_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "react_bucket" {
  depends_on = [
    aws_s3_bucket_ownership_controls.react_bucket,
    aws_s3_bucket_public_access_block.react_bucket,
  ]

  bucket     = aws_s3_bucket.react_bucket.id
  acl        = "public-read"
}

// Uploading react application to S3 bucket
//
locals {
  # Maps file extensions to mime types
  # Need to add more if needed
  mime_type_mappings = {
    html = "text/html",
    js   = "text/javascript",
    css  = "text/css"
  }
}
resource "aws_s3_object" "frontend_object" {
  for_each = fileset("${data.external.frontend_build.working_dir}/build", "**")
  bucket = aws_s3_bucket.react_bucket.id
  key    = each.value
  acl    = "public-read"
  source = "${data.external.frontend_build.working_dir}/${data.external.frontend_build.result.dest}/${each.value}"
  etag = filemd5("${data.external.frontend_build.working_dir}/${data.external.frontend_build.result.dest}/${each.value}")
  content_type = lookup(local.mime_type_mappings, concat(regexall("\\.([^\\.]*)$", each.value), [[""]])[0][0], "application/octet-stream")
}

/*
 * CloudFront distribution for react application
 */

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "my-react-app OAI"
}

locals {
  s3_origin_id = "weather-react-app-YS1MCTE"
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "example"
  description                       = "Example Policy"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.react_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  tags = {
    Environment = "test"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
