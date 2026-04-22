# 1. CLOUDWATCH DASHBOARD
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "NotesApp-Dashboard-${local.env}"

  dashboard_body = jsonencode({
    widgets = [
      # --- API GATEWAY METRICS ---
      {
        type = "metric"
        x    = 0, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "5XXError", "ApiName", "notes-http-api"],
            [".", "4XXError", ".", "."],
            [".", "Count", ".", "."],
            [".", "DataProcessed", ".", "."],
            [".", "Unauthorized", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "API Gateway: Errors & Traffic"
          period  = 300
        }
      },
      {
        type = "metric"
        x    = 12, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiName", "notes-http-api"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "API Gateway: Latency"
          period  = 300
        }
      },

      # --- LAMBDA METRICS ---
      {
        type = "metric"
        x    = 0, y = 6, width = 12, height = 6
        properties = {
          metrics = [
            for key in keys(local.lambdas) : ["AWS/Lambda", "Invocations", "FunctionName", "notes-${key}-${local.env}"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Lambda: Invocations"
          period  = 300
        }
      },
      {
        type = "metric"
        x    = 12, y = 6, width = 12, height = 6
        properties = {
          metrics = [
            for key in keys(local.lambdas) : ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", "notes-${key}-${local.env}"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Lambda: Concurrent Executions & Throttles"
        }
      },

      # --- LAMBDA LOGS INSIGHTS (Cold Starts & Memory) ---
      {
        type = "log"
        x    = 0, y = 12, width = 24, height = 6
        properties = {
          query         = "filter @type = 'REPORT' | stats max(@memorySize / 1000000) as MaxMemoryAllocatedMB, max(@maxMemoryUsed / 1000000) as MaxMemoryUsedMB, avg(@initDuration) as AvgColdStartTimeMS by @logStream | sort AvgColdStartTimeMS desc"
          region        = "us-east-1"
          stacked       = false
          title         = "Lambda: Cold Starts & Memory Usage (Logs Insights)"
          view          = "table"
          logGroupNames = [for key in keys(local.lambdas) : "/aws/lambda/notes-${key}-${local.env}"]
        }
      },

      # --- DYNAMODB METRICS ---
      {
        type = "metric"
        x    = 0, y = 18, width = 24, height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", module.dynamodb_table.dynamodb_table_id],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "SuccessfulRequestLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "DynamoDB: Capacity & Latency"
          period  = 300
        }
      }
    ]
  })
}

# 2. CLOUDWATCH ALARMS
resource "aws_cloudwatch_metric_alarm" "api_gw_5xx" {
  alarm_name          = "api-gateway-5xx-errors-${local.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This metric monitors API Gateway for 5XX Server Errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = "notes-http-api"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "lambda-throttles-${local.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Monitors if any Lambda functions are being throttled"
  treat_missing_data  = "notBreaching"
}
