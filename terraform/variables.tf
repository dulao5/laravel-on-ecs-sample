# aws configure

# name prefix
variable "name_prefix" {
  type        = string
  default     = "laravel-on-ecs"
  description = "Name prefix"
}

# aws region
variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "aws_azs" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "AWS Availability Zones"
}
  
variable "aws_vpc_cidr" {
  type        = string
  default     = "172.50.0.0/16"
  description = "AWS VPC CIDR"
}

variable "aws_private_subnets" {
  type        = list(string)
  default     = ["172.50.1.0/24", "172.50.2.0/24", "172.50.3.0/24"]
  description = "AWS Private Subnets"
}

variable "aws_public_subnets" {
  type        = list(string)
  default     = ["172.50.101.0/24", "172.50.102.0/24", "172.50.103.0/24"]
  description = "AWS Public Subnets"
}

## tags 
variable "tags" {
    type = map(string)
    default = {
        "Owner" = "zhigang.du@pingcap.com", //"laravel-on-ecs",
        "Project" = "laravel-on-ecs",
        "Environment" = "test",
    }
    description = "The tags to be added to the resources"
}

## bastion allow ssh from
variable "bastion_allow_ssh_from" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

## db infos
variable "db_settings" {
  type        = map(string)
  default     = {
    "aurora_db_name" = "test",
    "aurora_db_user" = "test",
    "aurora_db_password" = "test1234",
    "tidb_db_name" = "test",
    "tidb_db_user" = "test",
    "tidb_db_password" = "test1234",
    "tidb_db_host" = "testendpoint.tidbcloud.com",
    "tidb_db_port" = "4000",
  }
}

## ecr info
variable "ecr_settings" {
  type        = map(string)
  default     = {
    "php_ecr_repo_url" = "729581434105.dkr.ecr.us-west-2.amazonaws.com/laravel-on-ecs-dzg-php",
    "php_ecr_repo_tag" = "latest",
    "nginx_ecr_repo_url" = "729581434105.dkr.ecr.us-west-2.amazonaws.com/laravel-on-ecs-dzg-nginx",
    "nginx_ecr_repo_tag" = "latest",
    "nginx_ecr_repo_url" = "729581434105.dkr.ecr.us-west-2.amazonaws.com/laravel-on-ecs-dzg-proxysql",
    "nginx_ecr_repo_tag" = "latest",
  }
}