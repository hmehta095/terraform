data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner] # Bitnami
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["us-west-2a","us-west-2b","us-west-2c"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}


module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.1"

  name = "${var.environment.name}-blog"

  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = module.blog_vpc.public_subnets
  autoscaling_group_tags    = module.blog_alb.target_groups
  security_groups     = [module.blog_sg.security_group_id]
  instance_type       = var.instance_type
  image_id            = data.aws_ami.app_ami.id
}

module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.17.0"

  name = "${var.environment.name}-blog-alb"

  load_balancer_type = "application"

  vpc_id             = module.blog_vpc.vpc_id
  subnets            = module.blog_vpc.public_subnets
  security_groups    = [module.blog_sg.security_group_id]

  target_groups = {
    ex-instance = {
      name_prefix      = "${var.environment.name}-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      target_id        = data.aws_ami.app_ami.id
    }
  }

  listeners = {
    ex-http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "80"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = {
    Environment = var.environment.name
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.13.0"

  vpc_id  = module.blog_vpc.vpc_id
  name    = "${var.environment.name}-blog"
  ingress_rules = ["https-443-tcp","http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}
