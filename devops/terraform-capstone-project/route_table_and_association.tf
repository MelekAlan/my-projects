####################################
#  ROUTE TABLES
####################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tf_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "tf-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.tf_vpc.id
  
  tags = {
    Name = "tf-private-rt"
  }

  route {
    cidr_block  = "0.0.0.0/0"
    instance_id = aws_instance.bastion.id
  }

}

############################################
#  ROUTE TABLE ASSOCATİON
############################################

resource "aws_route_table_association" "public" {
  count          = length(var.subnet_cidr_public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.subnet_cidr_private)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private.id
}