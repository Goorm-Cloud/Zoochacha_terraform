terraform{
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

# vpc 정의
resource "aws_vpc" "this" {
  cidr_block = "10.50.0.0/16"                                          
  enable_dns_hostnames = true                      # dns 호스트 네임 활성화
  enable_dns_support = true            # dns 확인 활성화

  # 태그
  tags = {
    Name = "eks-vpc"
  }
}

# IGW 생성
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "eks-vpc-igw"
  }
}

# NATGW를 위한 탄력 IP 생성
resource "aws_eip" "this" {
    lifecycle {
        create_before_destroy = true
        #재성성시 먼저 새로운 eip를 하나 만들고 기존것을 삭제    
    }

    tags = {
        Name = "eks-vpc-eip" # 네임테그 생성
    }
}

# 퍼블릭 서브넷 생성 2A
resource "aws_subnet" "pub_sub1" {
  vpc_id = aws_vpc.this.id                      # 위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
  cidr_block = "10.50.10.0/24"               # 서브넷 CIDR
  map_public_ip_on_launch = true                                                  # 퍼블릭 IP 자동 할당
  enable_resource_name_dns_a_record_on_launch = true              # 레코드 A 활성화
  availability_zone = "ap-northeast-2a"                                          # 서브넷 가용 영역

  # 리소스 태그
  tags = {
    Name = "pub-sub1"

    # 쿠버네티스 클러스터 구성시 필요한 태그
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.ir/role/elb" = "1"
  }

  # 생성, 삭제 우선순위
  depends_on = [ aws_internet_gateway.this ]
}

# 퍼블릭 서브넷 생성 2C
resource "aws_subnet" "pub_sub2" {
  vpc_id = aws_vpc.this.id                      # 위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
  cidr_block = "10.50.11.0/24"               # 서브넷 CIDR
  map_public_ip_on_launch = true                                                  # 퍼블릭 IP 자동 할당
  enable_resource_name_dns_a_record_on_launch = true              # 레코드 A 활성화
  availability_zone = "ap-northeast-2c"                                          # 서브넷 가용 영역

  # 리소스 태그
  tags = {
    Name = "pub-sub2"

    # 쿠버네티스 클러스터 구성시 필요한 태그
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.ir/role/elb" = "1"
  }

  # 생성, 삭제 우선순위
  depends_on = [ aws_internet_gateway.this ]
}




# 프라이빗 서브넷 생성 2A
resource "aws_subnet" "pri_sub1" {
  vpc_id = aws_vpc.this.id                      # 위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
  cidr_block = "10.50.20.0/24"               # 서브넷 CIDR
  enable_resource_name_dns_a_record_on_launch = true              # 레코드 A 활성화
  availability_zone = "ap-northeast-2a"                                          # 서브넷 가용 영역

  # 리소스 태그
  tags = {
    Name = "pri-sub1"

    # 쿠버네티스 클러스터 구성시 필요한 태그
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.ir/role/elb" = "1"
  }

  # 생성, 삭제 우선순위
  depends_on = [ aws_internet_gateway.this ]
}

# 프라이빗 서브넷 생성 2C
resource "aws_subnet" "pri_sub2" {
  vpc_id = aws_vpc.this.id                      # 위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
  cidr_block = "10.50.21.0/24"               # 서브넷 CIDR
  enable_resource_name_dns_a_record_on_launch = true              # 레코드 A 활성화
  availability_zone = "ap-northeast-2c"                                          # 서브넷 가용 영역

  # 리소스 태그
  tags = {
    Name = "pri-sub2"

    # 쿠버네티스 클러스터 구성시 필요한 태그
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.ir/role/elb" = "1"
  }

  # 생성, 삭제 우선순위
  depends_on = [ aws_internet_gateway.this ]
}




# NAT 게이트웨이 생성
resource "aws_nat_gateway" "this" {
    allocation_id = aws_eip.this.id                       # 탄력 IP 의 this ID
    subnet_id     = aws_subnet.pub_sub1.id        # 배치할 서브넷 ID


    tags = {
        Name = "eks-vpc-natgw"
    }


    lifecycle {
      create_before_destroy = true
    }
}

# 퍼블릭 라우팅 테이블 생성
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "eks-vpc-pub-rt"
  }
}

# 프라이빗 라우팅 테이블 생성
resource "aws_route_table" "pri_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.this.id
  }
  tags = {
    Name = "eks-vpc-pri-rt"
  }
}

# 라우팅 테이블과 서브넷을 연결
# 퍼블릭 라우팅 테이블과 퍼블릭 서브넷을 연결
resource "aws_route_table_association" "pub1_rt_asso" {
  subnet_id = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub_rt.id
}
resource "aws_route_table_association" "pub2_rt_asso" {
  subnet_id = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.pub_rt.id
}

# 프라이빗 라우팅 테이블과 프라이빗 서브넷을 연결
resource "aws_route_table_association" "pri1_rt_asso" {
  subnet_id = aws_subnet.pri_sub1.id
  route_table_id = aws_route_table.pri_rt.id
}
resource "aws_route_table_association" "pri2_rt_asso" {
  subnet_id = aws_subnet.pri_sub2.id
  route_table_id = aws_route_table.pri_rt.id
}

# 보안그룹 생성
resource "aws_security_group" "eks-vpc-pub-sg" {
  vpc_id = aws_vpc.this.id
  name = "eks-vpc-pub-sg"
  tags = {
    Name = "eks-vpc-pub-sg"
  }
}

# http 인그리스 허용
resource "aws_security_group_rule" "eks-vpc-http-ingress" {
  type = "ingress"    # 보안그룹의 인바운드 규칙
  from_port = 80
  to_port = 80
  protocol = "TCP"
  cidr_blocks = [ "0.0.0.0/0" ]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}

# ssh 인그리스 허용
resource "aws_security_group_rule" "eks-vpc-ssh-ingress" {
  type = "ingress"    # 보안그룹의 인바운드 규칙
  from_port = 22
  to_port = 22
  protocol = "TCP"
  cidr_blocks = [ "0.0.0.0/0" ]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}

# 이그리스 허용
resource "aws_security_group_rule" "eks-vpc-all-engress" {
  type = "egress"    # 보안그룹의 아웃바운드 규칙
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = [ "0.0.0.0/0" ]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}