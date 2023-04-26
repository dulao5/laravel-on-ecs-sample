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

# Fargate Security Group rules
resource "aws_security_group_rule" "fargate_egress" {
  security_group_id = aws_security_group.fargate_sg.id

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# NLB Security Group rules
resource "aws_security_group_rule" "nlb_ingress" {
  security_group_id = aws_security_group.nlb_sg.id

  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# Aurora Security Group rules
resource "aws_security_group_rule" "aurora_ingress" {
  security_group_id = aws_security_group.aurora_sg.id

  type             = "ingress"
  from_port        = 3306
  to_port          = 3306
  protocol         = "tcp"
  source_security_group_id  = aws_security_group.fargate_sg.id
}

## allow fargate to access efs
resource "aws_security_group" "efs" {
  name_prefix = "efs-sg-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = [aws_security_group.fargate_sg.id]
  }

  egress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = [aws_security_group.fargate_sg.id]
  }

  tags = {
    Name = "EFS SG"
  }
}

# cloudwatch log group
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "${var.name_prefix}-ecs-log-group"
  tags = var.tags
}

## nginx->php , php->proxysql のための discovery service // いらないかも
resource "aws_service_discovery_private_dns_namespace" "ecs" {
  name        = "${var.name_prefix}.local"
  description = "${var.name_prefix} Namespace"
  vpc         = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "ecs" {
  name = "${var.name_prefix}-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.ecs.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

## ECS cluster

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name_prefix}-ecs-cluster"

  tags = var.tags
}

# IAM for ECS task
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]

  inline_policy {
    name = "ssm-control-and-ecr-token"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:OpenControlChannel"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

# EFS for proxysql socket
resource "aws_efs_file_system" "proxysql_socket" {
  creation_token = "${var.name_prefix}-efs"

  tags = var.tags
}

locals {
  private_subnets_map = { for index, subnet in module.vpc.private_subnets : "subnet${index + 1}" => subnet }
}

resource "aws_efs_mount_target" "proxysql_socket" {
  depends_on = [
    module.vpc
  ]
  for_each          = local.private_subnets_map
  file_system_id    = aws_efs_file_system.proxysql_socket.id
  subnet_id         = each.value
  security_groups   = [aws_security_group.efs.id]
}

## ECS task
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "${var.name_prefix}-ecs-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name = "nginx"
      image = "${var.ecr_settings["nginx_ecr_repo_url"]}:${var.ecr_settings["nginx_ecr_repo_tag"]}"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"  = "${aws_cloudwatch_log_group.ecs_log_group.name}"
          "awslogs-region" = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }

      linuxParameters = {
        initProcessEnabled = true # for use to ecs-exec
      }
    },
    {
      name  = "php"
      image = "${var.ecr_settings["php_ecr_repo_url"]}:${var.ecr_settings["php_ecr_repo_tag"]}"
      essential = true
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
        },
        // proxysql
        {
          name  = "PROXYSQL_SOCKET"
          value = "/var/lib/proxysql/proxysql.sock"
        },
        {
          name  = "PROXYSQL_TIDB_USER"
          value = "${var.db_settings["tidb_db_user"]}"
        },
        {
          name  = "PROXYSQL_TIDB_PASS"
          value = "${var.db_settings["tidb_db_password"]}"
        },
        {
          name  = "PROXYSQL_AURORA_USER"
          value = "${var.db_settings["aurora_db_user"]}"
        },
        {
          name  = "PROXYSQL_AURORA_PASS"
          value = "${var.db_settings["aurora_db_password"]}"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "proxysql-socket-efs-volume"
          containerPath = "/var/lib/proxysql"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"  = "${aws_cloudwatch_log_group.ecs_log_group.name}"
          "awslogs-region" = var.aws_region
          "awslogs-stream-prefix" = "php"
        }
      }

      linuxParameters = {
        initProcessEnabled = true # for use to ecs-exec
      }
    },
    {
      name = "proxysql"
      image = "${var.ecr_settings["proxysql_ecr_repo_url"]}:${var.ecr_settings["proxysql_ecr_repo_tag"]}"
      mountPoints = [
        {
          "sourceVolume" = "proxysql-socket-efs-volume"
          "containerPath" = "/var/lib/proxysql"
        }
      ]
      environment = [
        // aurora
        {
          name  = "BACKEND_AURORA_HOST"
          value = aws_rds_cluster.aurora_cluster.endpoint
        },
        {
          name  = "BACKEND_AURORA_PORT"
          value = "3306"
        },
        {
          name  = "BACKEND_AURORA_USER"
          value = "${var.db_settings["aurora_db_user"]}"
        },
        {
          name  = "BACKEND_AURORA_PASS"
          value = "${var.db_settings["aurora_db_password"]}"
        },
        // tidb
        {
          name  = "BACKEND_TiDB_HOST"
          value = "${var.db_settings["tidb_db_host"]}"
        },
        {
          name  = "BACKEND_TiDB_PORT"
          value = "4000"
        },
        {
          name  = "BACKEND_TiDB_USER"
          value = "${var.db_settings["tidb_db_user"]}"
        },
        {
          name  = "BACKEND_TiDB_PASS"
          value = "${var.db_settings["tidb_db_password"]}"
        },
        {
          name  = "Hoge"
          value = "fuga9"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"  = "${aws_cloudwatch_log_group.ecs_log_group.name}"
          "awslogs-region" = var.aws_region
          "awslogs-stream-prefix" = "proxysql"
        }
      }

      linuxParameters = {
        initProcessEnabled = true # for use to ecs-exec
      }
    }
  ])
  volume {
    name = "proxysql-socket-efs-volume"

    efs_volume_configuration {
      file_system_id = aws_efs_file_system.proxysql_socket.id
      root_directory = "/"
    }
  }
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
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nlb_target_group.arn
    container_name   = "nginx"
    container_port   = 80
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ecs.arn
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

  # for ECS service
  target_type = "ip"

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
  engine_version          = "5.7.mysql_aurora.2.10.3"
  availability_zones      = var.aws_azs
  database_name           = "${var.db_settings["aurora_db_name"]}"
  master_username         = "${var.db_settings["aurora_db_user"]}"
  master_password         = "${var.db_settings["aurora_db_password"]}"
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.aurora_sg.id]
  final_snapshot_identifier = "${var.name_prefix}-aurora-cluster-final-snapshot"

  db_subnet_group_name = aws_db_subnet_group.aurora_subnet_group.name

  tags = var.tags
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier         = "${var.name_prefix}-aurora-instance"
  engine             = "aurora-mysql"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.r5.2xlarge"

  tags = var.tags
}
