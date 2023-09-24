# Creation Dependencie:
# VPC - Subnet+IGW - RT
# VPC - Subnet+EIP+IGW - NGW - RT
# VPC - Subnet+SG - EC2
# AccessKey - EC2
# VPC - Subnet+SG - LB
# VPC - EC2 - TG - LB
# VPC - Subnet+SG+DBSubnetGroup - RDS

# 1. Create VPC
resource "aws_vpc" "vpc-cloud-fundamentals" {
  cidr_block = var.vpc_cidr
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc#enable_dns_support
  enable_dns_support = true
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc#enable_dns_hostnames
  enable_dns_hostnames = true
  tags = {
    Name = "vpc-cloud-fundamentals"
  }
}

# 2. Create Subnet
resource "aws_subnet" "subnet-public" {
  count             = length(var.subnet_cidr_public)
  vpc_id            = aws_vpc.vpc-cloud-fundamentals.id
  cidr_block        = var.subnet_cidr_public[count.index]
  availability_zone = var.availability_zone[count.index]
  tags = {
    "Name" = "subnet-public-${count.index + 1}"
  }
}

resource "aws_subnet" "subnet-private" {
  count                   = length(var.subnet_cidr_private)
  vpc_id                  = aws_vpc.vpc-cloud-fundamentals.id
  cidr_block              = var.subnet_cidr_private[count.index]
  availability_zone       = var.availability_zone[count.index]
  tags = {
    "Name" = "subnet-private-${count.index + 1}"
  }
}

# 3. Create Internet-Gateway
resource "aws_internet_gateway" "igw-web" {
  vpc_id = aws_vpc.vpc-cloud-fundamentals.id
  tags = {
    Name = "igw-web"
  }
}

# 4. Create Elastic IP
resource "aws_eip" "elastic-ip-nat-gateway" {
  count  = length(var.subnet_cidr_public)
  domain = "vpc"

  tags = {
    Name = "elastic-ip-nat-gateway-${count.index + 1}"
  }
}

# 5. Create NAT-Gateway
resource "aws_nat_gateway" "nat_gateway" {
  count         = length(var.subnet_cidr_public)
  subnet_id     = element(aws_subnet.subnet-public.*.id, count.index)
  allocation_id = aws_eip.elastic-ip-nat-gateway[count.index].id
  depends_on    = [aws_internet_gateway.igw-web]
  tags = {
    "Name" = "nat_gateway-${count.index + 1}"
  }
}

# 6. Create Route-Table
resource "aws_route_table" "rt-public" {
  vpc_id = aws_vpc.vpc-cloud-fundamentals.id
  tags = {
    Name = "rt-public"
  }
}

resource "aws_route_table" "rt-private" {
  count  = length(var.subnet_cidr_private)
  vpc_id = aws_vpc.vpc-cloud-fundamentals.id
  tags = {
    "Name" = "app-2-route-table-${count.index + 1}"
  }
}

# 7. Assign gateway to route table
resource "aws_route" "incoming-route" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.rt-public.id
  gateway_id             = aws_internet_gateway.igw-web.id
}

resource "aws_route" "outcoming-route" {
  count                  = length(var.subnet_cidr_private)
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.rt-private[count.index].id
  gateway_id             = aws_nat_gateway.nat_gateway[count.index].id
}

# 8. Assign subnet to route table
resource "aws_route_table_association" "public" {
  count          = length(var.subnet_cidr_public)
  subnet_id      = element(aws_subnet.subnet-public.*.id, count.index)
  route_table_id = aws_route_table.rt-public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.subnet_cidr_private)
  subnet_id      = element(aws_subnet.subnet-private.*.id, count.index)
  route_table_id = aws_route_table.rt-private[count.index].id
}

resource "aws_security_group" "security-group-load-balancer" {
  name        = "Allow_inbound_traffic_load_balancer"
  description = "Allow http inbound traffic from the internet to the load balancer"
  vpc_id      = aws_vpc.vpc-cloud-fundamentals.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security-group-load-balancer"
  }
}

# 9. Create security group to allow port: Http, Https, SSH, RDP
resource "aws_security_group" "security-group-web" {
  name        = "Allow_inbound_traffic"
  description = "Allow http inbound traffic from the load balancer to the EC2-instances"
  vpc_id      = aws_vpc.vpc-cloud-fundamentals.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   security_groups = [aws_security_group.security-group-load-balancer.id] # Keep the instance private by only allowing traffic from the load balancer.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security-group-web"
  }
}

resource "aws_security_group" "security-group-database" {
  name        = "Allow_inbound_traffic_database"
  description = "Allow mysql inbound traffic from the EC2-instances to the database"
  vpc_id      = aws_vpc.vpc-cloud-fundamentals.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.security-group-web.id] # Keep the instance private by only allowing traffic from the EC2-instances.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security-group-database"
  }
}

# 10.1 Create Amazon Linux-Apache2 EC2-instances
# Executing user_data requires internet access to install web-server. 
# Make sure that the EC2-instance uses a subnet which has internet access (NAT-Gateway, Internet-Gateway)
resource "aws_instance" "web-linux" {
  count         = length(var.subnet_cidr_public)
  ami           = "ami-03a6eaae9938c858c"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key_pair.key_name
  subnet_id     = element(aws_subnet.subnet-private.*.id, count.index)
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#associate_public_ip_address
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.security-group-web.id]
  user_data                   = file("user_data/user_data_linux.tpl")

  tags = {
    Name = "web-linux-${count.index + 1}"
  }
}

# 10.2 Create Windows-IIS EC2-instances
# Executing user_data requires internet access to install web-server. 
# Make sure that the EC2-instance uses a subnet which has internet access (NAT-Gateway, Internet-Gateway)
resource "aws_instance" "web-windows" {
  count         = length(var.subnet_cidr_public)
  ami           = "ami-0be0e902919675894"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key_pair.key_name
  subnet_id     = element(aws_subnet.subnet-private.*.id, count.index)
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#associate_public_ip_address
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.security-group-web.id]
  user_data                   = file("user_data/user_data_windows.tpl")

  tags = {
    Name = "web-windows-${count.index + 1}"
  }
}

# 11. Create Target Group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
resource "aws_lb_target_group" "target-group-front" {
  name     = "web-front"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-cloud-fundamentals.id
  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 10
    matcher             = 200
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 3
    unhealthy_threshold = 2
  }
}

# 12.1 Add Windows EC2-instances to created Target Group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment
resource "aws_lb_target_group_attachment" "attach-web-linux" {
  count            = length(aws_instance.web-linux)
  target_group_arn = aws_lb_target_group.target-group-front.arn
  target_id        = element(aws_instance.web-linux.*.id, count.index)
  port             = 80
}

# 12.2 Add Windows EC2-instances to created Target Group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment
resource "aws_lb_target_group_attachment" "attach-web-windows" {
  count            = length(aws_instance.web-windows)
  target_group_arn = aws_lb_target_group.target-group-front.arn
  target_id        = element(aws_instance.web-windows.*.id, count.index)
  port             = 80
}

# 13. Add Load Balancer
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "load-balancer-front" {
  name               = "front"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.security-group-load-balancer.id]
  subnets            = [for subnet in aws_subnet.subnet-public : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "load-balancer-front"
  }
}


# 14. Add Target Group to Load Balancer
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.load-balancer-front.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-group-front.arn
  }
}

# 15. Create Database Subnet Group
resource "aws_db_subnet_group" "db-subnet-group-mysql" {
  name       = "db-subnet-group-mysql"
  subnet_ids = aws_subnet.subnet-private.*.id
}

/* 
* 16. Create a RDS Database Instance
* allocated_storage: This is the amount in GB
* storage_type: Type of storage we want to allocate(options avilable "standard" (magnetic), "gp2" (general purpose SSD), or "io1" (provisioned IOPS SSD)
* engine: Database engine(for supported values check https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstance.html) eg: Oracle, Amazon Aurora,Postgres 
* engine_version: engine version to use
* instance_class: instance type for rds instance
* name: The name of the database to create when the DB instance is created.
* username: Username for the master DB user.
* password: Password for the master DB user
* db_subnet_group_name:  DB instance will be created in the VPC associated with the DB subnet group. If unspecified, will be created in the default VPC
* vpc_security_group_ids: List of VPC security groups to associate.
* allows_major_version_upgrade: Indicates that major version upgrades are allowed. Changing this parameter does not result in an outage and the change is asynchronously applied as soon as possible.
* auto_minor_version_upgrade:Indicates that minor engine upgrades will be applied automatically to the DB instance during the maintenance window. Defaults to true.
* backup_retention_period: The days to retain backups for. Must be between 0 and 35. When creating a Read Replica the value must be greater than 0
* backup_window: The daily time range (in UTC) during which automated backups are created if they are enabled. Must not overlap with maintenance_window
* maintainence_window: The window to perform maintenance in. Syntax: "ddd:hh24:mi-ddd:hh24:mi".
* multi_az: Specifies if the RDS instance is multi-AZ
* skip_final_snapshot: Determines whether a final DB snapshot is created before the DB instance is deleted. If true is specified, no DBSnapshot is created. If false is specified, a DB snapshot is created before the DB instance is deleted, using the value from final_snapshot_identifier. Default is false
 */
resource "aws_db_instance" "db-mysql" {
  identifier                  = "db-mysql-instance"
  allocated_storage           = 20
  storage_type                = "gp2"
  engine                      = "mysql"
  engine_version              = "8.0.33"
  instance_class              = "db.t2.micro"
  username                    = "admin"
  password                    = "admnin123"
  parameter_group_name        = "default.mysql8.0"
  db_subnet_group_name        = aws_db_subnet_group.db-subnet-group-mysql.name
  vpc_security_group_ids      = [aws_security_group.security-group-database.id]
  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true
  backup_retention_period     = 35
  backup_window               = "22:00-23:00"
  maintenance_window          = "Sat:00:00-Sat:03:00"
  multi_az                    = true
  skip_final_snapshot         = true
  publicly_accessible         = true
}