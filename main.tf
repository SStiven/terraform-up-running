provider "aws" {
    region = "us-east-1"
}

variable "www-port" {
    description = "port for www server"
    type = number
    default = 80
}

variable "www-port-list" {
    description = "list of www ports"
    type = list(number)
    default = [80, 8080]
}

resource "aws_key_pair" "sstiven-key" {
  key_name   = "ec2-key"
  public_key = file("ec2-key.pub")
}

resource "aws_security_group" "ssh_access" {
  name        = "ssh-access-sg"
  description = "Security group for SSH access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_security_group" "allow-web-access" {
    name = "HTTP and HTTPS access from anywhere"

    ingress {
        from_port = var.www-port-list[0]
        to_port = var.www-port-list[0]
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow HTTP access from anywhere"
    }

    ingress {
        from_port = var.www-port-list[1]
        to_port = var.www-port-list[1]
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow HTTP access from anywhere"
    }

    egress {
        from_port   = var.www-port-list[0]
        to_port     = var.www-port-list[0]
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow all outbound traffic"
    }

    egress {
        from_port   = var.www-port-list[1]
        to_port     = var.www-port-list[1]
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow all outbound traffic"
    }

}

resource "aws_instance" "name_001" {
    ami = "ami-058bd2d568351da34" //Debian 12
    instance_type = "t2.micro"
    associate_public_ip_address = true

    vpc_security_group_ids = [aws_security_group.allow-web-access.id, aws_security_group.ssh_access.id]
    key_name = aws_key_pair.sstiven-key.key_name

    user_data = <<-EOF
        #!/bin/bash
        apt-get update
        apt-get install -y nginx
        echo "Hello, World!" > /var/www/html/index.html
        systemctl enable nginx
        systemctl start nginx
        EOF
    
    tags = {
        Name = "web-app"
        Environment = "ssh-enabled"
    }
}

output "public_ip" {
    value = aws_instance.name_001.public_ip
    description = "The public IP address of the web server"
}


#Let's create an autoscaling group and all it's requirements

data "aws_vpc" "default" {
    default = true
}

data "aws_subnets" "default" {
    filter {
      name = "vpc-id"
      values = [data.aws_vpc.default.id]
    }
}

resource "aws_launch_configuration" "launch_config_one" {
    image_id = "ami-058bd2d568351da34"
    instance_type = "t2.micro"
    security_groups = [aws_security_group.allow-web-access.id]

    user_data = <<-EOF
        #!/bin/bash
        apt-get update
        apt-get install -y nginx
        echo "Hello, World!" > /var/www/html/index.html
        systemctl enable nginx
        systemctl start nginx
        EOF
}

resource "aws_autoscaling_group" "asg_one" {
    launch_configuration = aws_launch_configuration.launch_config_one.name
    vpc_zone_identifier = data.aws_subnets.default.ids
    target_group_arns = [aws_lb_target_group.alb-target-group-one.arn]
    health_check_type = "ELB" #EC2

    min_size = 2
    max_size = 3

    lifecycle {
      create_before_destroy = true
    }

    tag {
        key = "name"
        value = "terraform-asg-name"
        propagate_at_launch = true
    }
}


resource "aws_lb" "application-load-balancer-one" {
    name = "application-load-balancer-one"
    load_balancer_type = "application"
    subnets = data.aws_subnets.default.ids
    security_groups = [aws_security_group.alb_security_group_one.id]
}

resource "aws_lb_listener" "lb-http-listener" {
    load_balancer_arn = aws_lb.application-load-balancer-one.arn
    port = 80
    protocol = "HTTP"

    default_action {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "404: page not found"
        status_code = 404
      }
    }
}


resource "aws_security_group" "alb_security_group_one" {
    name = "alb_security_group_1"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb_target_group" "alb-target-group-one" {
    name = "alb-target-group-one"
    port = var.www-port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
      path = "/"
      protocol = "HTTP"
      matcher = "200"
      interval = 15
      timeout = 3
      healthy_threshold = 2
      unhealthy_threshold = 2
    }
}

resource "aws_lb_listener_rule" "lb_listener_rule_one" {
    listener_arn = aws_lb_listener.lb-http-listener.arn
    priority = 100
    condition {
        path_pattern {
            values = ["*"]
        }
    }
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.alb-target-group-one.arn
    }
}

output "alb_dns_name" {
    value = aws_lb.application-load-balancer-one.dns_name
    description = "The domain name of the load balancer"
}