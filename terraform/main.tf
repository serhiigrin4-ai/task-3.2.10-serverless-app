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

# Отримуємо ID твого поточного AWS-акаунту (щоб не хардкодити цифри)
data "aws_caller_identity" "current" {}

# 1. DYNAMODB TABLE
module "dynamodb_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 4.0"

  name         = "notes-app-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "noteId"

  attributes = [
    { name = "noteId", type = "S" }
  ]
}

# 2. ACM CERTIFICATE
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name = "*.serhiigrin4-games.pp.ua"
  zone_id     = "Z09164682UAIEK9VY8Q0Y"

  subject_alternative_names = [
    "serhiigrin4-games.pp.ua"
  ]

  validation_method   = "DNS"
  wait_for_validation = true
}

# 3. AWS LAMBDA
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
  handler       = "app.handler"
  runtime       = "nodejs18.x"
  source_path   = "../packages/backend"
  artifacts_dir = "builds/${each.key}"

  environment_variables = {
    NOTES_TABLE_NAME = module.dynamodb_table.dynamodb_table_id
  }

  # Перепустка для API Gateway (ВИПРАВЛЕНО)
  create_current_version_allowed_triggers = false
  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      principal  = "apigateway.amazonaws.com"
      source_arn = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:*/*"
    }
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

# 4. API GATEWAY
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

# 5. ROUTE 53 RECORD FOR API
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

# 6. S3 BUCKET FOR FRONTEND
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "serhiigrin4-notes-frontend-new"
  acl    = "private"

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  website = {
    index_document = "index.html"
    error_document = "index.html"
  }
}

# 7. CLOUDFRONT DISTRIBUTION
module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 3.0"

  aliases = ["notes.serhiigrin4-games.pp.ua"]

  comment             = "Notes App CloudFront"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  wait_for_deployment = false

  default_root_object = "index.html"

  custom_error_response = [
    {
      error_code         = 403
      response_code      = 200
      response_page_path = "/index.html"
    },
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]

  create_origin_access_control = true
  origin_access_control = {
    s3_oac = {
      description      = "CloudFront access to S3"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    s3_oac = {
      domain_name           = module.s3_bucket.s3_bucket_bucket_regional_domain_name
      origin_access_control = "s3_oac"
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3_oac"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    query_string           = false
  }

  viewer_certificate = {
    acm_certificate_arn      = module.acm.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# 8. ROUTE 53 RECORD FOR FRONTEND
resource "aws_route53_record" "frontend_dns" {
  zone_id = "Z09164682UAIEK9VY8Q0Y"
  name    = "notes.serhiigrin4-games.pp.ua"
  type    = "A"

  alias {
    name                   = module.cloudfront.cloudfront_distribution_domain_name
    zone_id                = module.cloudfront.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

# 9. S3 BUCKET POLICY FOR CLOUDFRONT OAC
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.s3_bucket.s3_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_oac_policy" {
  bucket = module.s3_bucket.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_policy.json
}
