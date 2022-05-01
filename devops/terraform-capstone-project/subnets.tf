#######################################
#  PUBLİC AND PRİVATE SUBNETS
#######################################

resource "aws_subnet" "public" {
  count                   = length(var.subnet_cidr_public)
  vpc_id                  = aws_vpc.tf_vpc.id
  cidr_block              = var.subnet_cidr_public[count.index]
  availability_zone       = var.AZ[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = length(var.subnet_cidr_private)
  vpc_id            = aws_vpc.tf_vpc.id
  cidr_block        = var.subnet_cidr_private[count.index]
  availability_zone = var.AZ[count.index]
}

############################
# RD SUBNET 
###########################

resource "aws_db_subnet_group" "rd-subnet" {
  name       = "db-subnet-tf"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  tags = {
    Name = "rd-subnet"
  }
}