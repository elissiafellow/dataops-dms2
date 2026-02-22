### Requester's side of the connection.
resource "aws_vpc_peering_connection" "requester_connection" {
  provider                  = aws.src
  vpc_id        = var.vpc_id
  peer_vpc_id   = var.peer_vpc_id
  peer_owner_id = var.peer_owner_id
  peer_region   = var.peer_region
  auto_accept   = false
  tags = {
    Side = "Requester"
  }
}

### Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "accepter_connection" {
  provider                  = aws.dst
  vpc_peering_connection_id = aws_vpc_peering_connection.requester_connection.id
  auto_accept               = true
  tags = {
    Side = "Accepter"
  }
}

### Accepter route
resource "aws_route" "accepter_route" {
  provider                  = aws.dst
  route_table_id            = var.accepter_route_table_id
  destination_cidr_block    = var.requestor_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.requester_connection.id
}

resource "aws_route" "requestor_route" {
  provider                  = aws.src
  route_table_id            = var.route_table_id
  destination_cidr_block    = var.acceptor_cidr_block
  vpc_peering_connection_id =    aws_vpc_peering_connection.requester_connection.id
}

resource "aws_vpc_peering_connection_options" "requester_connection" {
  provider                  = aws.src
  vpc_peering_connection_id = aws_vpc_peering_connection.requester_connection.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
  requester {
    allow_remote_vpc_dns_resolution = true
  }
  depends_on = [aws_vpc_peering_connection_accepter.accepter_connection]
}