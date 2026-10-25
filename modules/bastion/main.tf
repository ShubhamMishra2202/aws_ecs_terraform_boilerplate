# ─── Bastion (SSM only) ───────────────────────────────────────────────────────
# A tiny instance inside the VPC for reaching private resources (RDS).
# No SSH key, no inbound rules, no public IP. Access is through SSM Session
# Manager, authenticated by IAM and logged by CloudTrail:
#
#   aws ssm start-session --target <instance_id> \
#     --document-name AWS-StartPortForwardingSessionToRemoteHost \
#     --parameters host=<rds_address>,portNumber=5432,localPortNumber=5433
#
# Then connect to localhost:5433. Stop the instance when idle.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_iam_role" "bastion" {
  name = "${var.name}-bastion"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "Bastion: no ingress; egress for SSM agent and forwarded connections"
  vpc_id      = var.vpc_id

  egress {
    description = "SSM endpoints (via NAT) and targets inside the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-bastion" }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = "${var.name}-bastion" }
}
