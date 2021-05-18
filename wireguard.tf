terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

data "aws_ami" "alpine" {
  most_recent = true
  owners      = ["538276064493"]

  filter {
    name   = "name"
    values = ["alpine-ami-*"]
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

data "template_file" "wireguard_script" {
  template = file("templates/user_data.sh")
  depends_on = [ random_integer.wgport ]

  vars = {
    client = var.wgclient
    port   = random_integer.wgport.result
  }
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

resource "random_integer" "wgport" {
  min = 1025
  max = 65535
}

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
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.client_ip]
  }

  ingress {
    description = "allow wireguard"
    from_port   = random_integer.wgport.result
    to_port     = random_integer.wgport.result
    protocol    = "udp"
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
  ami                         = data.aws_ami.alpine.id
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
    data.template_file.wireguard_script,
  ]
}

resource "null_resource" "wireguard_install" {
  triggers = {
    public_ip = aws_instance.wireguard_ec2.public_ip
  }

  connection {
    host        = aws_instance.wireguard_ec2.public_ip
    type        = "ssh"
    user        = "alpine"
    private_key = tls_private_key.wireguard_ssh_privkey.private_key_pem
    agent       = true
  }

  provisioner "file" {
    destination = "/tmp/wireguard.sh"
    content = data.template_file.wireguard_script.rendered
  }

  provisioner "remote-exec" {
    inline = [ <<EOC
sudo chmod +x /tmp/wireguard.sh
sudo /tmp/wireguard.sh
cat <<EOL
[Peer]
PublicKey = $(cat /opt/wireguard/server-pub)
Endpoint = ${aws_instance.wireguard_ec2.public_ip}:${random_integer.wgport.result}
AllowedIPs = 0.0.0.0/0, ::/0
EOL
EOC
]
  }
}
