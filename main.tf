resource "aws_acm_certificate" "example" {
  domain_name               = "example.com"
  subject_alternative_names = ["www.example.com", "example.org"]
  validation_method         = "DNS"
}

resource "aws_route53_zone" "example_com" {
  name = "example.com"
}

resource "aws_route53_zone" "example_org" {
  name = "example.org"
}

resource "aws_route53_record" "example" {
  for_each = {
    for dvo in aws_acm_certificate.example.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = dvo.domain_name == "example.org" ? resource.aws_route53_zone.example_org.zone_id : resource.aws_route53_zone.example_com.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

resource "aws_acm_certificate_validation" "example" {
  certificate_arn         = aws_acm_certificate.example.arn
  validation_record_fqdns = [for record in aws_route53_record.example : record.fqdn]
}

data "archive_file" "lambda_hello_world" {
  type = "zip"

  source_dir  = "${path.module}/hello-world"
  output_path = "${path.module}/hello-world.zip"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "my-tf-test-bucket"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "lambda_hello_world" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "hello-world.zip"
  source = data.archive_file.lambda_hello_world.output_path

  etag = filemd5(data.archive_file.lambda_hello_world.output_path)
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
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

resource "aws_lambda_function" "hello_world" {
  function_name = "HelloWorld"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_hello_world.key

  runtime = "nodejs20.x"
  handler = "hello.handler"

  source_code_hash = data.archive_file.lambda_hello_world.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "hello_world" {
  name = "/aws/lambda/${aws_lambda_function.hello_world.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_api_gateway_rest_api" "forgerock" {
  name        = "ForgeRock"
  description = "ForgeRock API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "forgerock" {
  rest_api_id = aws_api_gateway_rest_api.forgerock.id
  parent_id   = aws_api_gateway_rest_api.forgerock.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "forgerock" {
  rest_api_id   = aws_api_gateway_rest_api.forgerock.id
  resource_id   = aws_api_gateway_resource.forgerock.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "forgerock" {
  rest_api_id             = aws_api_gateway_rest_api.forgerock.id
  resource_id             = aws_api_gateway_resource.forgerock.id
  http_method             = aws_api_gateway_method.forgerock.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello_world.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_deployment" "forgerock" {
  rest_api_id = aws_api_gateway_rest_api.forgerock.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.forgerock.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "forgerock" {
  deployment_id = aws_api_gateway_deployment.forgerock.id
  rest_api_id   = aws_api_gateway_rest_api.forgerock.id
  stage_name    = "forgerock"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name

  principal     = "apigateway.amazonaws.com"
  source_arn = "arn:aws:execute-api:eu-west-1:000000000000:${aws_api_gateway_rest_api.forgerock.id}/*/${aws_api_gateway_method.forgerock.http_method}${aws_api_gateway_resource.forgerock.path}"
}

resource "aws_api_gateway_domain_name" "forgerock" {
  regional_certificate_arn = aws_acm_certificate_validation.example.certificate_arn
  domain_name              = "www.example.com"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "backend" {
  api_id      = aws_api_gateway_rest_api.forgerock.id
  domain_name = aws_api_gateway_domain_name.forgerock.domain_name
}
