variable "key-name" {
  type        = string
  description = "The AWS key pair to use for resources."
}

variable "ami" {
  type = map(string)
  #   type = "map"
  description = "A map of AMIs."
  default     = {}
}

variable "instance-type" {
  type        = string
  description = "The instance type."
  default     = "t2.micro"
}

variable "region" {
  type        = string
  description = "The AWS region."
}

variable "AZ" {
  description = "The AWS region."
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  default = "20.0.0.0/16"
}

variable "subnet_cidr_public" {
  description = "Subnet CIDRs for public subnets (length must match configured availability_zones)"
  default     = ["20.0.1.0/24", "20.0.3.0/24"]
}

variable "subnet_cidr_private" {
  description = "Subnet CIDRs for private subnets (length must match configured availability_zones)"
  default     = ["20.0.2.0/24", "20.0.4.0/24"]
}

variable "blog-bucket" {
  default = "meleksblog"      #  PLEASE ENTER YOUR FIRST BUCKET NAME
}

variable "s3-failover" {
  default = "capstone.melek-alan.com"    # PLEASE ENTER YOUR SECOND BUCKET NAME IT MUST BE SAME NAME WITH YOUR SUBDOMAIN NAME
}


data "aws_ami" "tf-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10*"]
  }
}

variable "db-password" {
  default = "XXXXXXXXXX"    # PLEASE ENTER YOUR DATABASE PASSWORD
}

variable "ubuntu-ami" {
  default = "ami-0e472ba40eb589f49"
}

variable "nat-ami" {
  default = "ami-003acd4f8da7e06f9"
}

variable "S3hostedzoneID" {
  default = "Z3AQBSTGFYJSTF"

}

variable "S3websiteendpoint" {
  default = "s3-website-us-east-1.amazonaws.com"
}

variable "domain_name" {
  default = "melek-alan.com"   #  PLEASE ENTER YOUR DOMAİN NAME
}

variable "subdomain_name" {
  default = "capstone.melek-alan.com"    #  PLEASE ENTER YOUR FULL SUBDOMAİN NAME
}
variable "awsAccount" {
  default = "XXXXXXXXXXXX"    # PLEASE ENTER YOUR AWS ACCOUNT ID WİTHOUT '-'
}

