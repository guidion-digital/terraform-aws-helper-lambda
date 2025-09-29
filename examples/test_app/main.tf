resource "aws_iam_role" "test_app" {
  name = "test_app"

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
      },
    ]
  })
}

module "helper_lambda" {
  source = "../../"

  name             = "test_app"
  application_name = "test_app"

  specification = {
    runtime                        = "python3.9"
    source_dir                     = "dist"
    function_name                  = "test-app"
    handler                        = "debug.handler"
    role_arn                       = aws_iam_role.test_app.arn
    vpc_enabled                    = false
    reserved_concurrent_executions = 10
    memory_size                    = 512
    timeout                        = 300

    common_endpoint_configuration = {
      request_validator = "*"
    }

    environment = {
      "DEBUG" = "true"
    }

    security_group_rules = {
      ingress = {
        "all" = {
          protocol  = "-1"
          cidr      = "0.0.0.0/0"
          from_port = -1
          to_port   = -1
        }
      }
    }

    endpoints = {
      "debug" = {
        "GET /debug" = {
          http_method = "GET"
          security    = ["debug"]
          headers = {
            "Content-Type" = {
              schema = {
                type = "string"
              }
            }
          }

          responses = {
            "200" = {
              description = "Successful response"
              headers = {
                "Content-Type" = {
                  schema = {
                    type = "string"
                  }
                }
              }
            }
          }

        }
      }
    }
  }

  tags = {
    Environment = "test"
  }
}

output "paths_spec" {
  value = module.helper_lambda.paths_spec
}

output "all" {
  value = module.helper_lambda
}
