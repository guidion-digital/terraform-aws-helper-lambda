output "lambda_arn" {
  value = aws_lambda_function.this.arn
}

output "lambda_version" {
  value = aws_lambda_function.this.version
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "lambda_qualified_arn" {
  value = aws_lambda_function.this.qualified_arn
}

output "lambda_invoke_arn" {
  value = aws_lambda_function.this.invoke_arn
}

output "lambda_qualified_invoke_arn" {
  value = aws_lambda_function.this.qualified_invoke_arn
}

output "paths_spec" {
  description = "OpenAPI paths spec for use in the API Gateway resource body"
  value       = local.paths_spec
}

output "specification" {
  description = "Pass back all values in the specification given. Useful when you need these inputs for another resource after this module creates the Lambda"
  value       = var.specification
}

locals {
  # We are constructing a section of the OpenAPI specification. Specifically, a
  # 'path' object: https://swagger.io/specification/#paths-object
  paths_spec = {
    for endpoint, definition in var.specification.endpoints : endpoint => {
      for this_method, this_method_config in definition : this_method => {
        # https://swagger.io/specification/#security-requirement-object
        security = [for this_scheme in this_method_config.security : {
          (this_scheme) = []
        }],

        parameters = [for this_parameter in
          {
            for this_param_name, these_param_values in this_method_config.parameters :
            this_param_name => {
              name     = this_param_name,
              in       = these_param_values.in,
              required = these_param_values.required,
              schema   = these_param_values.schema
            }
          } : this_parameter
        ],

        # https://swagger.io/specification/#responses-object
        #
        # If this is a mock integration, fill in the necessary headers. Still
        # allow for overrides and additions via merge()
        responses = this_method_config.integration.type == "mock" ? merge(
          this_method_config.responses,
          {
            "200" = {
              "description" = "200 response",
              "headers" = {
                "Access-Control-Allow-Origin" = {
                  value  = ""
                  schema = { type = "string" }
                },
                "Access-Control-Allow-Methods" = {
                  value  = "",
                  schema = { type = "string" }
                },
                "Access-Control-Allow-Headers" = {
                  value  = this_method_config.AccessControlAllowMethods,
                  schema = { type = "string" }
                }
              }
            }
        }) : this_method_config.responses

        # https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-request-validator.html
        "x-amazon-apigateway-request-validator" = this_method_config.request_validator != null ? this_method_config.request_validator : var.specification.common_endpoint_configuration.request_validator,

        # Create an integration object:
        # https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration.html
        #
        "x-amazon-apigateway-integration" = {
          type       = this_method_config.integration.type
          httpMethod = this_method_config.http_method == null ? "POST" : null
          passthroughBehavior : "when_no_match",
          uri = this_method_config.integration.type != "mock" ? (var.specification.publish_version ? aws_lambda_function.this.qualified_invoke_arn : aws_lambda_function.this.invoke_arn) : null

          # https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration-responses.html
          #
          # N.B. The special case of "mock" integrations can only handle a single
          # response; "200"
          responses = this_method_config.integration.type == "mock" ? {
            for this_code, these_response_values in this_method_config.responses :
            "default" => {
              "statusCode" = this_code,
              # Fill in 'Access-Control-Allow-Methods' value as all the verbs in
              # this endpoint, and the 'Access-Control-Allow-Headers' with what
              # AWS expects. This still allows for overrides and via merge()
              "responseParameters" = merge(
                {
                  # We make a special case for AccessAccess-Control-Allow-Methods
                  # to enable the cheat-code field AccessControlAllowMethods to
                  # be parsed.
                  #
                  # If it's missing, we fill it in from all the methods
                  # known about in this endpoint, but bear in mind that this will
                  # only work as expected if there are not multiple definitions
                  # for the endpoint (for multiple Lambdas), otherwise only the
                  # last method will be added. This is due to the way the deepmerge
                  # module works
                  "method.response.header.Access-Control-Allow-Methods" = this_method_config.AccessControlAllowMethods != null ? this_method_config.AccessControlAllowMethods : "'${upper(join(", ", [for endpoint, definition in var.specification.endpoints : replace(join(", ", [for this_method, this_method_config in definition : this_method]), " ", "")]))}'",
                  "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent,X-Amzn-Trace-Id'",
                  "method.response.header.Access-Control-Allow-Origin"  = "'*'"
                },
                {
                  for this_header, these_values in these_response_values["headers"] :
                  "method.response.header.${this_header}" => these_values["value"]
              }, )
            }
          } : this_method_config.integration.responses,

          requestTemplates = this_method_config.integration.type == "mock" ? { "application/json" = "{statusCode:200}" } : this_method_config.integration.request_templates
          contentHandling  = this_method_config.integration.type == "mock" ? "CONVERT_TO_TEXT" : this_method_config.integration.content_handling
        }
      }
    }
  }
}
