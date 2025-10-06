variable "name" {
  description = "The name for the Lambda"
}

variable "application_name" {
  description = "Name of the application this Lambda is for"
}

variable "specification" {
  description = "Map describing Lambda to API relations"

  type = object({
    publish_version                = optional(bool, true),
    latest_version_alias           = optional(string, "live"),
    runtime                        = string,
    source_dir                     = string,
    function_name                  = string,
    handler                        = string,
    role_arn                       = string,
    reserved_concurrent_executions = optional(number, -1),
    memory_size                    = optional(number),
    timeout                        = optional(number),
    environment                    = optional(map(string), {}),
    vpc_enabled                    = bool,
    security_group_rules = optional(object({
      egress = optional(map(object({
        protocol  = optional(string, "-1"),
        cidr      = optional(string, "0.0.0.0/0"),
        from_port = optional(number, 0),
        to_port   = optional(number, 0)
        })
        ), {
        "all" = {
          protocol  = "-1",
          cidr      = "0.0.0.0/0",
          from_port = -1,
          to_port   = -1
        }
      }),
      ingress = optional(map(object({
        protocol  = string,
        cidr      = string,
        from_port = number,
        to_port   = number
        })
      ), {}),
      }
    ), {}),

    common_endpoint_configuration = optional(object({
      request_validator = optional(string)
    }), {}),

    endpoints = optional(map(map(object({
      security    = optional(list(string), []),
      http_method = optional(string)
      responses = optional(map(object({
        description = string,
        headers = optional(map(object({
          value = optional(string),
          schema = optional(object({
            type = optional(string, "string")
            }), {
            schema = {
              type = "string"
            }
          })
          # Not implemented
          # content = optional(map(object({
          #   schema   = optional(any),
          #   example  = optional(any),
          #   examples = optional(any),
          #   encoding = optional(map(string))
          # }))),
          # links = optional(map(string), {})
        })), {})
        })),
        {
          "200" = {
            "description" = "200 response",
          }
      }),
      # This is a cheat for when we don't want to be so verbose as to take the
      # header value from the above responses.headers object
      AccessControlAllowMethods = optional(string),
      request_validator         = optional(string),
      integration = optional(object({
        type = optional(string, "aws_proxy"),
        responses = optional(map(
          object({
            statusCode         = string,
            responseParameters = map(string)
          })),
        {})
        request_templates = optional(map(string)),
        content_handling  = optional(string)
        }
      ), {}),
      parameters = optional(map(object({
        in       = optional(string, "query"),
        required = optional(bool, true),
        schema   = optional(map(string), { "type" = "string" })
      })), {})
    }))))

    vpc_config = optional(object({
      subnet_ids         = optional(list(string), []),
      security_group_ids = optional(list(string), []),
      vpc_id             = optional(list(string), [])
    }), {})
  })

  # TODO: This can probably work if we get rid of the default values in the optional
  #       fields above and from the calling variable they come from
  # validation {
  #   condition = length(
  #     [
  #       for this_field, this_value in var.specification : []
  #       if this_value == null && this_field != "environments"
  #     ]
  #   ) == 0 ? true : false
  #   error_message = "One or more mandatory fields are missing"
  # }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}
