data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.specification.source_dir
  excludes    = ["${path.module}/terraform"]
  output_path = "${path.module}/${var.name}.zip"
}

### Resources

resource "aws_security_group" "this" {
  count = var.specification.vpc_enabled ? 1 : 0

  name   = var.specification.function_name
  vpc_id = var.specification.vpc_config.vpc_id[0]
  tags   = var.tags
}

resource "aws_vpc_security_group_egress_rule" "egress" {
  for_each = var.specification.vpc_enabled ? var.specification.security_group_rules.egress : {}

  description       = each.key
  security_group_id = one(aws_security_group.this).id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ingress" {
  for_each = var.specification.vpc_enabled ? var.specification.security_group_rules.ingress : {}

  description       = each.key
  security_group_id = one(aws_security_group.this).id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  depends_on = [data.archive_file.this]

  publish                        = var.specification.publish_version
  filename                       = "${path.module}/${var.name}.zip"
  function_name                  = lookup(var.specification, "function_name")
  role                           = lookup(var.specification, "role_arn")
  handler                        = var.specification.handler
  runtime                        = var.specification.runtime
  source_code_hash               = data.archive_file.this.output_base64sha256
  memory_size                    = var.specification.memory_size
  reserved_concurrent_executions = var.specification.reserved_concurrent_executions
  timeout                        = var.specification.timeout

  dynamic "environment" {
    for_each = var.specification.environment == {} ? [] : [var.specification.environment]

    content {
      variables = environment.value
    }
  }

  dynamic "vpc_config" {
    for_each = var.specification.vpc_config == {} ? [] : [var.specification.vpc_config]

    content {
      subnet_ids         = vpc_config.value["subnet_ids"]
      security_group_ids = concat([for this_sg in aws_security_group.this : this_sg.id], vpc_config.value["security_group_ids"])
    }
  }

  tags = var.tags
}

resource "aws_lambda_alias" "live" {
  count = var.specification.publish_version ? 1 : 0

  name             = var.specification.latest_version_alias
  description      = "Live version of the function"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}
