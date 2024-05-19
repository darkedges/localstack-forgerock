output "base_url" {
  description = "Base URL for API Gateway stage."
  value = format("http://%s.execute-api.localhost.localstack.cloud:4566/%s%s", aws_api_gateway_rest_api.forgerock.id,aws_api_gateway_stage.forgerock.stage_name,aws_api_gateway_resource.forgerock.path)
}
