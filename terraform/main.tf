terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. DYNAMODB TABLE
module "dynamodb_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 4.0"

  name         = "notes-app-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attributes = [
    { name = "id", type = "S" }
  ]
}

# 2. ACM CERTIFICATE
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name       = "api.serhiigrin4-games.pp.ua"
  zone_id           = "Z09164682UAIEK9VY8Q0Y"
  validation_method = "DNS"
}

# 3. AWS LAMBDA (5 Functions)
locals {
  lambdas = {
    "create" = { method = "POST", path = "/notes" }
    "list"   = { method = "GET", path = "/notes" }
    "get"    = { method = "GET", path = "/notes/{id}" }
    "update" = { method = "PUT", path = "/notes/{id}" }
    "delete" = { method = "DELETE", path = "/notes/{id}" }
  }
}

module "lambda_functions" {
  source   = "terraform-aws-modules/lambda/aws"
  version  = "~> 7.0"
  for_each = local.lambdas

  function_name = "notes-${each.key}"
  handler       = "${each.key}.handler"
  runtime       = "nodejs18.x"
  source_path   = "../packages/backend"

  environment_variables = {
    TABLE_NAME = module.dynamodb_table.dynamodb_table_id
  }

  attach_policy_statements = true
  policy_statements = {
    dynamodb = {
      effect    = "Allow"
      actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Scan", "dynamodb:DeleteItem", "dynamodb:UpdateItem"]
      resources = [module.dynamodb_table.dynamodb_table_arn]
    }
  }
}

# 4. API GATEWAY (HTTP API)
module "api_gateway" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 3.0"

  name          = "notes-http-api"
  protocol_type = "HTTP"

  domain_name                 = "api.serhiigrin4-games.pp.ua"
  domain_name_certificate_arn = module.acm.acm_certificate_arn

  cors_configuration = {
    allow_headers = ["content-type", "x-amz-date", "authorization", "x-api-key"]
    allow_methods = ["*"]
    allow_origins = ["*"]
  }

  integrations = {
    for key, val in local.lambdas : "${val.method} ${val.path}" => {
      lambda_arn             = module.lambda_functions[key].lambda_function_arn
      payload_format_version = "2.0"
    }
  }
}

# 5. ROUTE 53 RECORD
resource "aws_route53_record" "api_dns" {
  zone_id = "Z09164682UAIEK9VY8Q0Y"
  name    = "api.serhiigrin4-games.pp.ua"
  type    = "A"

  alias {
    name                   = module.api_gateway.apigatewayv2_domain_name_configuration[0].target_domain_name
    zone_id                = module.api_gateway.apigatewayv2_domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
