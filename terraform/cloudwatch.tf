locals {
  lambda_keys = ["create", "delete", "get", "list", "update"]
}

# ---------------------------------------------------------
# 1. CLOUDWATCH DASHBOARD (Тільки стабільні метрики)
# ---------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "NotesApp-Monitoring-${local.env}"

  dashboard_body = jsonencode({
    widgets = concat(

      # ---------------- API GATEWAY ----------------
      [
        {
          type = "metric", x = 0, y = 0, width = 12, height = 6
          properties = {
            metrics = [
              ["AWS/ApiGateway", "5XXError", "ApiName", "notes-http-api"],
              [".", "4XXError", ".", "."],
              [".", "Count", ".", "."],
              [".", "Latency", ".", "."],
              [".", "DataProcessed", ".", "."],
              [".", "Unauthorized", ".", "."]
            ]
            stat   = "Sum"
            period = 300
            region = "us-east-1"
            title  = "API Gateway Metrics"
          }
        }
      ],

      # ---------------- LAMBDA METRICS ----------------
      [
        for i, name in local.lambda_keys : {
          type   = "metric"
          x      = (i % 2) * 12
          y      = 6 + (floor(i / 2) * 6)
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/Lambda", "Invocations", "FunctionName", "notes-${name}-${local.env}"],
              [".", "Errors", ".", "."],
              [".", "Throttles", ".", "."],
              [".", "Duration", ".", "."],
              [".", "ConcurrentExecutions", ".", "."]
            ]
            stat   = "Average"
            period = 300
            region = "us-east-1"
            title  = "Lambda: notes-${name}-${local.env}"
          }
        }
      ],

      # ---------------- COLD STARTS ----------------
      [
        {
          type = "metric", x = 0, y = 24, width = 24, height = 6
          properties = {
            metrics = [
              for name in local.lambda_keys :
              ["Custom/Lambda", "ColdStartCount-${name}"]
            ]
            stat   = "Sum"
            period = 300
            region = "us-east-1"
            title  = "Lambda Cold Starts"
          }
        }
      ],

      # ---------------- DYNAMODB ----------------
      [
        {
          type = "metric", x = 0, y = 30, width = 24, height = 6
          properties = {
            metrics = [
              ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", module.dynamodb_table.dynamodb_table_id],
              [".", "ConsumedWriteCapacityUnits", ".", "."],
              [".", "SuccessfulRequestLatency", ".", "."]
            ]
            stat   = "Average"
            period = 300
            region = "us-east-1"
            title  = "DynamoDB Metrics"
          }
        }
      ]
    )
  })
}

# ---------------------------------------------------------
# 2. COLD START METRIC FILTERS
# ---------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "cold_start" {
  for_each       = toset(local.lambda_keys)
  name           = "cold-start-${each.key}-${local.env}"
  log_group_name = "/aws/lambda/notes-${each.key}-${local.env}"

  pattern = "Init Duration"

  metric_transformation {
    name      = "ColdStartCount-${each.key}"
    namespace = "Custom/Lambda"
    value     = "1"
    # БЕЗ dimensions - це ключ до відсутності 400-х помилок!
  }
}

# ---------------------------------------------------------
# 3. ALARMS
# ---------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "api-5xx-${local.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  dimensions = {
    ApiName = "notes-http-api"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(local.lambda_keys)

  alarm_name          = "lambda-errors-${each.key}-${local.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  dimensions = {
    FunctionName = "notes-${each.key}-${local.env}"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = toset(local.lambda_keys)

  alarm_name          = "lambda-throttles-${each.key}-${local.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  dimensions = {
    FunctionName = "notes-${each.key}-${local.env}"
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "dynamodb-throttles-${local.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  dimensions = {
    TableName = module.dynamodb_table.dynamodb_table_id
  }
}
