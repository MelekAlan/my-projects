terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.9.0"
    }
    github = {
      source  = "integrations/github"
      version = "4.23.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "github" {
  token = "XXXXXXXXXXXXXXXXXXXXXX"  #  PLEASE ENTER YOUR GITHUB TOKEN
}


############################
#  VPC
############################

resource "aws_vpc" "tf_vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"
  tags = {
    Name = "tf_vpc"
  }
  enable_dns_hostnames = true
  enable_dns_support   = true
}

######################################
#  INTERNET GATEWAY AND ATTACHMENT
######################################

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.tf_vpc.id

  tags = {
    Name = "tf_igw"
  }
}

###########################################
#  VPC ENDPOINT / ROUTE TABLE ASSOCİATİON
###########################################

resource "aws_vpc_endpoint" "tf-endpoint-s3" {
  vpc_id            = aws_vpc.tf_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  #policy default full access
}


resource "aws_vpc_endpoint_route_table_association" "ft-route-table" {
  route_table_id  = aws_route_table.private.id
  vpc_endpoint_id = aws_vpc_endpoint.tf-endpoint-s3.id
}

###################################################
#  FIRST S3 BLOG BUCKET AND BUCKET NOTIFICATION
####################################################

resource "aws_s3_bucket" "s3-blog" {
  bucket = var.blog-bucket
  acl    = "public-read"
  policy = file("policy/policys3lambda.json")
  depends_on = [
    aws_lambda_function.lambda-tf
  ]
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.s3-blog.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda-tf.arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix       = "media/"
  }

  depends_on = [
    aws_lambda_permission.lambda-invoke
  ]
}

##################################
#  FAILOVER BUCKET
#################################

resource "aws_s3_bucket" "s3-failover" {
  bucket = var.subdomain_name
  acl    = "public-read"
  policy = file("policy/policy.json")

  website {
    index_document = "index.html"
    error_document = "index.html"
  }
}

####################################
#  S3 FAILOVER OBJECTS LOAD
##################################


resource "aws_s3_bucket_object" "sorry" {
  bucket       = aws_s3_bucket.s3-failover.bucket
  key          = "sorry.jpg"
  source       = "html/sorry.jpg"
  content_type = "text/html"
  etag         = filemd5("html/sorry.jpg")
  acl          = "public-read"
}

resource "aws_s3_bucket_object" "index" {
  bucket       = aws_s3_bucket.s3-failover.bucket
  key          = "index.html"
  source       = "html/index.html"
  content_type = "text/html"
  etag         = md5(file("html/index.html"))
  acl          = "public-read"
}

###########################
# BASTION INSTANCE
###########################

resource "aws_instance" "bastion" {
  ami               = var.nat-ami
  key_name          = var.key-name
  instance_type     = var.instance-type
  subnet_id         = aws_subnet.public[0].id
  security_groups   = [aws_security_group.bastion-sec.id]
  source_dest_check = false
  tags = {
    Name = "Bastion-Instance"
  }
}

################################
#  RDS
################################

resource "aws_db_instance" "rds-tf" {
  allocated_storage           = 20
  engine                      = "mysql"
  engine_version              = "8.0.28"
  instance_class              = "db.t2.micro"
  db_name                     = "database1"
  identifier                  = "database1"
  username                    = "admin"
  password                    = var.db-password
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  skip_final_snapshot         = true # default false 
  port                        = 3306
  vpc_security_group_ids      = [aws_security_group.rds-sec.id]
  db_subnet_group_name        = aws_db_subnet_group.rd-subnet.name
}

##########################################
# IAM ROLE FOR EC2-FIRST S3 FULL ACCESS
##########################################

resource "aws_iam_role" "ec2-s3" {
  name = "ec2-s3-full-tf"
  path = "/"
  assume_role_policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Principal" = {
          "Service" = "ec2.amazonaws.com"
        },
        "Action" = "sts:AssumeRole"
        "Sid"    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3-full" {
  name = "s3-full-tf"
  role = aws_iam_role.ec2-s3.id
  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Action" = [
          "s3:*",
          "s3-object-lambda:*"
        ],
        "Resource" = "*"
      }
    ]
  })
}

#############################
# IAM INSTANCE PROFILE
############################

resource "aws_iam_instance_profile" "instance-role" {
  name = "instance-role"
  role = aws_iam_role.ec2-s3.name
}

##############################
# LAUNCH TEMPLATE
##############################

resource "aws_launch_template" "tf-lt" {
  name                   = "tf-lt"
  instance_type          = var.instance-type
  image_id               = var.ubuntu-ami
  key_name               = var.key-name
  vpc_security_group_ids = [aws_security_group.ec2-sec.id]
  user_data              = filebase64("./userdata.sh")
  depends_on = [
    github_repository_file.dbendpoint,
    aws_instance.bastion
  ]
  iam_instance_profile {
    name = aws_iam_instance_profile.instance-role.name
  }
}

###########################
#  GİTHUB
###########################

resource "github_repository_file" "dbendpoint" {
  content             = aws_db_instance.rds-tf.address
  file                = "src/cblog/dbserver.endpoint"
  repository          = "capstone-tf"
  overwrite_on_create = true
  branch              = "main"
}

##################################
# CERTIFICATE MANAGER 
##################################

# Find a certificate that is isssued

data "aws_acm_certificate" "isssued" {
  domain = var.domain_name
  statuses = ["ISSUED" ]
}

# To use exist hosted zone 

data "aws_route53_zone" "zone" {
  name         = var.domain_name
  private_zone = false
}

#------------------------------------------------------------------------------
# If you want to create new cert and create cname record to your hosted zone,
# You can use this code bloks, i prefer to use my exist acm cert
#------------------------------------------------------------------------------- 

# resource "aws_acm_certificate" "cert" {
#   domain_name       = var.subdomain_name
#   validation_method = "DNS"
#   tags = {
#     "Name" = var.subdomain_name
#   }
#   lifecycle {
#     create_before_destroy = true
#   }
# }

# resource "aws_route53_record" "cert_validation" {
#   depends_on      = [aws_acm_certificate.cert]
#   zone_id         = data.aws_route53_zone.zone.id
#   name            = sort(aws_acm_certificate.cert.domain_validation_options[*].resource_record_name)[0]
#   type            = "CNAME"
#   ttl             = "300"
#   records         = [sort(aws_acm_certificate.cert.domain_validation_options[*].resource_record_value)[0]]
#   allow_overwrite = true

# }

# resource "aws_acm_certificate_validation" "cert" {
#   certificate_arn = aws_acm_certificate.cert.arn
#   validation_record_fqdns = [
#     aws_route53_record.cert_validation.fqdn
#   ]
#   timeouts {
#     create = "60m"
#   }
# }

###############################
#  APPLICATION LOAD BALANCER
###############################

resource "aws_lb" "alb-tf" {
  name               = "alb-tf"
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb-sec.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
}


###############################
# LISTENER RULES
###############################

resource "aws_lb_listener" "tf-https" {
  load_balancer_arn = aws_lb.alb-tf.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.isssued.arn  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tf-target.arn
  }
  # depends_on = [
  #   aws_acm_certificate.cert
  # ]
}

resource "aws_lb_listener" "tf-http" {
  load_balancer_arn = aws_lb.alb-tf.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


###############################
#  TARGET GROUP
##############################

resource "aws_lb_target_group" "tf-target" {
  name        = "tf-target"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.tf_vpc.id
  health_check {
    protocol            = "HTTP"         # default HTTP
    port                = "traffic-port" # default
    unhealthy_threshold = 2              # default 3
    healthy_threshold   = 5              # default 3
    interval            = 20             # default 30
    timeout             = 5              # default 10
  }
}

################################
# AUTOSCALING GROUP AND POLICY
################################

resource "aws_autoscaling_group" "asg-tf" {
  name                      = "asg-tf"
  max_size                  = 4
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = [aws_lb_target_group.tf-target.arn]
  depends_on = [
    aws_instance.bastion
  ]
  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]
  launch_template {
    id      = aws_launch_template.tf-lt.id
    version = "$Default"
  }
}

resource "aws_autoscaling_policy" "policy-tf" {
  name                   = "asg-policy-tf"
  autoscaling_group_name = aws_autoscaling_group.asg-tf.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

#################################
#  CLOUDFRONT
################################

locals {
  alb_origin_id = "ALBOriginId"
}

resource "aws_cloudfront_distribution" "cf-tf" {

  origin {
    domain_name = aws_lb.alb-tf.dns_name
    origin_id   = local.alb_origin_id

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_ssl_protocols     = ["TLSv1"]
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "match-viewer"
    }
  }

  price_class = "PriceClass_All"
  enabled = true
  comment = "Cloudfront Distribution pointing to ALBDNS"
  aliases = [var.subdomain_name]
  depends_on = [
    aws_autoscaling_group.asg-tf
  ]


  default_cache_behavior {
    target_origin_id       = local.alb_origin_id
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    max_ttl                = 86400
    default_ttl            = 3600
    smooth_streaming       = false
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      headers = ["Host", "Accept", "Accept-Charset", "Accept-Datetime", "Accept-Encoding", "Accept-Language", "Authorization", "Cloudfront-Forwarded-Proto", "Origin", "Referrer"]
    }
    compress = true
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.isssued.arn 
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
    cloudfront_default_certificate = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

####################################
# ROUTE 53 HEALTH CHECK
####################################

resource "aws_route53_health_check" "tf-health" {
  type = "HTTP"
  port = 80
  fqdn = aws_cloudfront_distribution.cf-tf.domain_name
  request_interval = 30
  tags = {
    Name = "${var.s3-failover}-healthcheck"
  }
}

# ##################################
# #  ROUTE 53 AND HOSTED ZONE
# ##################################


resource "aws_route53_record" "primary" {
  zone_id         = data.aws_route53_zone.zone.zone_id
  name            = "capstone"
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.tf-health.id
  depends_on = [
    aws_cloudfront_distribution.cf-tf
  ]

  alias {
    name                   = aws_cloudfront_distribution.cf-tf.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  zone_id        = data.aws_route53_zone.zone.zone_id
  name           = "capstone"
  set_identifier = "Secondary"
  type           = "A"
  depends_on = [
    aws_cloudfront_distribution.cf-tf
  ]
  alias {
    name                   = "s3-website-us-east-1.amazonaws.com"
    zone_id                = "Z3AQBSTGFYJSTF"
    evaluate_target_health = true
  }
  failover_routing_policy {
    type = "SECONDARY"
  }
}

####################################
# LAMBDA ROLE AND POLICIES
###################################

resource "aws_iam_role" "iam_for_lambda" {
  name               = "lambda-role-for-s3"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda-s3-dynamodb" {
  name = "lambda-s3-dynamodb"
  role = aws_iam_role.iam_for_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Effect = "Allow"
        Resource = ["*"]
      }
    ]

    Statement = [
      {
        Action = [
          "lambda:Invoke*"
        ]
        Effect = "Allow"
        Resource = ["*"]
      }
    ]
#-------------------------------------------------------
# To create inline policy  we can use this code blocks
#-------------------------------------------------------

    # Statement = [
    #   {
    #     Action = ["dynamodb:GetItem",
    #               "dynamodb:PutItem",
    #               "dynamodb:UpdateItem"
    #     ]
    #     Effect = "Allow"
    #     Resource = ["arn:aws:dynamodb:*:*:table/awscapstoneDynamo"]
    #   }
    # ]
  })
}

# data "aws_iam_policy_document" "lambda-s3-dynamodb" {
#   statement {
#     actions = ["s3:PutObject","s3:GetObject","s3:GetObjectVersion"]
#     resources = [ "*" ]
#   }

#   statement {
#     actions   = ["lambda:Invoke*"]
#     resources = [ "*" ]
#   }

#   statement {
#     actions = [ "dynamodb:GetItem",
#                 "dynamodb:PutItem",
#                 "dynamodb:UpdateItem"]
#     resources = [ "arn:aws:dynamodb:*:*:*" ]
#   }

#   statement {
#     actions = [ "s3:*",
#                 "s3-object-lambda:*"]
#     resources = [ "*" ]
#   }
# }

resource "aws_iam_role_policy_attachment" "role-policy-attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/job-function/NetworkAdministrator",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ])
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = each.value
}


##############################
# LAMBDA FUNCTION
#############################

data "archive_file" "zipit" {
  type        = "zip"
  source_file = "./lambda.py"
  output_path = "lambda.zip"
}

resource "aws_lambda_function" "lambda-tf" {
  filename         = "lambda.zip"
  source_code_hash = data.archive_file.zipit.output_base64sha256
  role             = aws_iam_role.iam_for_lambda.arn
  runtime          = "python3.8"
  function_name    = "lambda-function"
  handler          = "index.handler"
  vpc_config {
    subnet_ids         = [aws_subnet.public[0].id, aws_subnet.public[1].id, aws_subnet.private[0].id, aws_subnet.private[1].id]
    security_group_ids = [aws_security_group.bastion-sec.id]
  }
}

resource "aws_lambda_permission" "lambda-invoke" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda-tf.function_name
  source_arn     = aws_s3_bucket.s3-blog.arn
  source_account = var.awsAccount
  principal      = "s3.amazonaws.com"
}


##############################
#  DYNAMODB TABLE
##############################

resource "aws_dynamodb_table" "dynamodb-tf" {
  name           = "awscapstoneDynamo"
  hash_key       = "id"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  attribute {
    name = "id"
    type = "S"
  }
}



