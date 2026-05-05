# Alarms + dashboard. The log group itself is created at the env layer to
# avoid a module cycle (ECS needs the log group name; observability needs
# ECS cluster/service names for alarms).
# Two alarms only — both signal something the on-call should actually look at:
#   1) Sustained high CPU on the service (load issue / runaway loop).
#   2) ALB 5xx — the user-facing contract is broken.
# More alarms would just be noise on a demo. Real systems should add p99 latency,
# 4xx ratio, target-group unhealthy host count, etc.

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.name}-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "ECS service CPU >80% for 3 minutes."
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_description   = "More than 5 target 5xx responses in 1 minute (sustained 2 minutes)."
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  tags = var.tags
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "ECS service CPU & memory"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
        }
      },
      {
        type = "metric"
        x    = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB request count & 5xx"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
        }
      },
      {
        type = "log"
        x    = 0, y = 6, width = 24, height = 6
        properties = {
          title  = "Recent app logs"
          region = var.region
          query  = "SOURCE '${var.log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          view   = "table"
        }
      }
    ]
  })
}
