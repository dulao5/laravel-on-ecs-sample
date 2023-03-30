# vpc settings

# using terraform aws vpc module
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.3.0"

  name = "${var.name_prefix}-vpc-${var.aws_region}"

  cidr = var.aws_vpc_cidr

  azs             = var.aws_azs
  private_subnets = var.aws_private_subnets
  public_subnets  = var.aws_public_subnets

  enable_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}

## security groups

resource "aws_security_group" "fargate_sg" {
  name        = "${var.name_prefix}-fargate-sg"
  description = "Security group for Fargate service"
  vpc_id      = module.vpc.vpc_id

  tags = var.tags
}

resource "aws_security_group" "nlb_sg" {
  name        = "${var.name_prefix}-nlb-sg"
  description = "Security group for Network Load Balancer"
  vpc_id      = module.vpc.vpc_id

  tags = var.tags
}

resource "aws_security_group" "aurora_sg" {
  name        = "${var.name_prefix}-aurora-sg"
  description = "Security group for Aurora database"
  vpc_id      = module.vpc.vpc_id

  tags = var.tags
}

## ECS cluster

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name_prefix}-ecs-cluster"

  tags = var.tags
}

## ECS task
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "${var.name_prefix}-ecs-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name = "${var.name_prefix}-nginx"
      image = "${var.ecr_settings["nginx_ecr_repo_url"]}:${var.ecr_settings["nginx_ecr_repo_tag"]}"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      links = [
        "php:php"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"  = "/ecs/${var.name_prefix}-nginx"
          "awslogs-region" = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name  = "${var.name_prefix}-app"
      image = "${var.ecr_settings["php_ecr_repo_url"]}:${var.ecr_settings["php_ecr_repo_tag"]}"
      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
        }
      ]
      environment = [
        // aurora
        {
          name  = "AURORA_DB_HOST"
          value = aws_rds_cluster.aurora_cluster.endpoint
        },
        {
          name  = "AURORA_DB_PORT"
          value = "3306"
        },
        {
          name  = "AURORA_DB_NAME"
          value = "${var.db_settings["aurora_db_name"]}"
        },
        {
          name  = "AURORA_DB_USER"
          value = "${var.db_settings["aurora_db_user"]}"
        },
        {
          name  = "AURORA_DB_PASSWORD"
          value = "${var.db_settings["aurora_db_password"]}"
        },
        // tidb
        {
          name  = "TiDB_DB_HOST"
          value = "${var.db_settings["tidb_db_host"]}"
        },
        {
          name  = "TiDB_DB_PORT"
          value = "4000"
        },
        {
          name  = "TiDB_DB_NAME"
          value = "${var.db_settings["tidb_db_name"]}"
        },
        {
          name  = "TiDB_DB_USER"
          value = "${var.db_settings["tidb_db_user"]}"
        },
        {
          name  = "TiDB_DB_PASSWORD"
          value = "${var.db_settings["tidb_db_password"]}"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"  = "/ecs/${var.name_prefix}-app"
          "awslogs-region" = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

## ECS service
resource "aws_ecs_service" "ecs_service" {
  name            = "${var.name_prefix}-ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = 10
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.fargate_sg.id, aws_security_group.aurora_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nlb_target_group.arn
    container_name   = "${var.name_prefix}-app"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.nlb_listener
  ]

  tags = var.tags
}

## NLB
resource "aws_lb" "nlb" {
  name               = "${var.name_prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets

  tags = var.tags
}

## Target group
resource "aws_lb_target_group" "nlb_target_group" {
  name     = "${var.name_prefix}-nlb-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 30
    path                = "/healthcheck"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
  }

  tags = var.tags
}

## NLB listener
resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_target_group.arn
  }
}

## Aurora database

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "${var.name_prefix}-aurora-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = var.tags
}

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier      = "${var.name_prefix}-aurora-cluster"
  engine                  = "aurora-mysql"
  engine_version          = "5.7.mysql_aurora.2.11.1"
  availability_zones      = var.aws_azs
  database_name           = "${var.db_settings["aurora_db_name"]}"
  master_username         = "${var.db_settings["aurora_db_user"]}"
  master_password         = "${var.db_settings["aurora_db_password"]}"
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.aurora_sg.id]

  db_subnet_group_name = aws_db_subnet_group.aurora_subnet_group.name

  tags = var.tags
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier         = "${var.name_prefix}-aurora-instance"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.t3.small"

  tags = var.tags
}