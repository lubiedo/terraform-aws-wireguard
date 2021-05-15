terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] // canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "client_ip" {
  type = string
}
variable "wgclient" {
  type = string
}

provider "aws" {
  region     = var.aws_region
  access_key = local.aws_access_key
  secret_key = local.aws_secret_key
  default_tags {
    tags = {
      createdby = "terraform"
      purpose   = "wireguard_vpn"
    }
  }
}

data "aws_region" "current" {}

resource "tls_private_key" "wireguard_ssh_privkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_key_pair" "wireguard_ssh_pubkey" {
  key_name   = "wireguard_ssh"
  public_key = tls_private_key.wireguard_ssh_privkey.public_key_openssh
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_vpc" "wireguard_vpc" {
  cidr_block = "10.10.0.0/16"
}

resource "aws_subnet" "wireguard_subnet" {
  vpc_id     = aws_vpc.wireguard_vpc.id
  cidr_block = "10.10.10.0/24"
}

resource "aws_internet_gateway" "wireguard_igw" {
  vpc_id = aws_vpc.wireguard_vpc.id
}

resource "aws_route_table" "wireguard_rtb" {
  vpc_id = aws_vpc.wireguard_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wireguard_igw.id
  }
}

resource "aws_main_route_table_association" "wireguard_rtbassoc" {
  vpc_id         = aws_vpc.wireguard_vpc.id
  route_table_id = aws_route_table.wireguard_rtb.id
}

resource "aws_network_acl" "wireguard_nacl" {
  vpc_id = aws_vpc.wireguard_vpc.id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.client_ip
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 101
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = -1
    rule_no    = 200
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

resource "aws_security_group" "wireguard_sg" {
  name   = "wireguard_allow_all"
  vpc_id = aws_vpc.wireguard_vpc.id

  ingress {
    description = "allow all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.client_ip]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_instance" "wireguard_ec2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = "wireguard_ssh"
  subnet_id                   = aws_subnet.wireguard_subnet.id

  credit_specification {
    cpu_credits = "unlimited"
  }

  vpc_security_group_ids = [
    aws_security_group.wireguard_sg.id
  ]

  depends_on = [
    aws_security_group.wireguard_sg,
    aws_key_pair.wireguard_ssh_pubkey,
  ]
}

resource "null_resource" "wireguard_install" {
  triggers = {
    public_ip = aws_instance.wireguard_ec2.public_ip
  }

  connection {
    host        = aws_instance.wireguard_ec2.public_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.wireguard_ssh_privkey.private_key_pem
    agent       = true
  }

  provisioner "file" {
    source      = "wireguard_init.sh"
    destination = "/tmp/wireguard_init.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt update ; sudo apt update",
      "sudo apt install -y wireguard wireguard-tools wireguard-dkms ifupdown resolvconf",
      "chmod +x /tmp/wireguard_init.sh",
      "sudo /tmp/wireguard_init.sh ${var.wgclient}",
    ]
  }
}

# info for user
output "instance_privkey" {
  value = tls_private_key.wireguard_ssh_privkey.private_key_pem
}
output "instance_ip" {
  value = aws_instance.wireguard_ec2.public_ip
}
