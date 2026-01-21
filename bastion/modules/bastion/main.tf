data "aws_ssm_parameter" "latest_al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

data "aws_eks_cluster" "eks_cluster" {
  name = var.eks_cluster_name
}

locals {
  vpc_id    = data.aws_eks_cluster.eks_cluster.vpc_config[0].vpc_id
  subnet_id = var.subnet_id != "" ? var.subnet_id : tolist(data.aws_eks_cluster.eks_cluster.vpc_config[0].subnet_ids)[0]
}

data "aws_security_group" "eks_cluster_sg" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "tag:kubernetes.io/cluster/${var.eks_cluster_name}"
    values = ["owned"]
  }

  filter {
    name   = "group-name"
    values = ["eks-cluster-sg-${var.eks_cluster_name}-*"]
  }

}

resource "aws_security_group" "bastion_sg" {
  name   = var.bastion_name
  vpc_id = local.vpc_id
  description = "Security group for bastion host"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.additional_tags
}

resource "aws_instance" "bastion_instance" {
  ami                    = (var.instance_ami_id != "" ? var.instance_ami_id : data.aws_ssm_parameter.latest_al2023_ami.value)
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name
  root_block_device {
    encrypted = true
  }
  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("files/bastion_user_data.tftpl", {
    aws_region                      = var.aws_region,
    eks_cluster_name                = var.eks_cluster_name,
    tailscale_auth_key              = var.auth_key,
    bastion_name                    = var.bastion_name,
    cloudwatch_audit_enable         = var.cloudwatch_audit_enable,
    cloudwatch_audit_retention_days = var.cloudwatch_audit_retention_days
  })

  tags = merge({
    Name = var.bastion_name
    },
    var.additional_tags
  )
}

resource "aws_security_group_rule" "bastion_eks_access_sg_rule" {
  security_group_id = data.aws_security_group.eks_cluster_sg.id
  description       = "Allow access from byoc bastion host ${aws_instance.bastion_instance.id} to EKS cluster"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["${aws_instance.bastion_instance.private_ip}/32"]
}

resource "aws_eks_access_entry" "bastion_eks_access_entry" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion_role.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion_eks_access_policy_association" {
  cluster_name  = var.eks_cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${var.eks_cluster_access_policy}"
  principal_arn = aws_iam_role.bastion_role.arn

  access_scope {
    type = "cluster"
  }
}
