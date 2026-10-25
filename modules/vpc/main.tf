# ─── VPC ──────────────────────────────────────────────────────────────────────
#   public subnets  → Internet Gateway          (ALB, NAT)
#   private subnets → NAT → Internet Gateway    (ECS tasks, RDS, bastion)
# Nothing in a private subnet is reachable from the internet.
# Subnets are carved automatically: public = x.x.0-9.0/24, private = x.x.10-19.0/24.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  public_cidrs  = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, i)]
  private_cidrs = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, i + 10)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true # required for RDS endpoints and SSM
  enable_dns_support   = true

  tags = { Name = var.name }
}

# The default SG allows all traffic between its members. Strip every rule so
# nothing can accidentally rely on it.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name}-public-${var.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name}-private-${var.azs[count.index]}", Tier = "private" }
}

# ─── NAT ──────────────────────────────────────────────────────────────────────
# Lets private subnets call out (external APIs, ECR pulls, SSM) while blocking
# inbound. Also gives a stable egress IP third parties can allowlist.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}

# Option A: managed NAT Gateway
resource "aws_nat_gateway" "main" {
  count         = var.nat_type == "gateway" ? 1 : 0
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = var.name }

  depends_on = [aws_internet_gateway.main]
}

# Option B: NAT instance (Amazon Linux 2023 + iptables masquerade)
data "aws_ssm_parameter" "al2023_arm64" {
  count = var.nat_type == "instance" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "nat" {
  count       = var.nat_type == "instance" ? 1 : 0
  name        = "${var.name}-nat"
  description = "NAT instance: all traffic from inside the VPC, anything out"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "From VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr]
  }

  egress {
    description = "To internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-nat" }
}

resource "aws_instance" "nat" {
  count                       = var.nat_type == "instance" ? 1 : 0
  ami                         = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  associate_public_ip_address = true  # needed at boot to install iptables, replaced by the EIP
  source_dest_check           = false # must be off to forward traffic that isn't addressed to itself

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    until dnf install -y iptables-services; do sleep 5; done
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
    sysctl -p /etc/sysctl.d/90-nat.conf
    IFACE=$(ip route show default | awk '{print $5}')
    iptables -t nat -A POSTROUTING -o "$IFACE" -s ${var.cidr} -j MASQUERADE
    iptables -F FORWARD
    service iptables save
    systemctl enable --now iptables
  EOF

  lifecycle {
    ignore_changes = [ami] # don't replace the NAT every time AWS publishes an AMI
  }

  tags = { Name = "${var.name}-nat" }
}

resource "aws_eip_association" "nat" {
  count         = var.nat_type == "instance" ? 1 : 0
  allocation_id = aws_eip.nat.id
  instance_id   = aws_instance.nat[0].id
}

# ─── Routing ──────────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-private" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_type == "gateway" ? aws_nat_gateway.main[0].id : null
  network_interface_id   = var.nat_type == "instance" ? aws_instance.nat[0].primary_network_interface_id : null
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
