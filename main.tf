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

resource "aws_key_pair" "mykey" {
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
    name = "terraform-example-sg"

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
    key_name = aws_key_pair.mykey.key_name

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

