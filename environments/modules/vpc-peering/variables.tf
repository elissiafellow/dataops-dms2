variable "vpc_id" {
  type        = string
}
variable "peer_vpc_id" {
  type        = string
}
variable "peer_owner_id" {
  type        = string
}
variable "peer_region" {
  type        = string
}
variable "acceptor_cidr_block" {
  type        = string
}
variable "route_table_id" {
  type        = string
}
variable "requestor_cidr_block" {
  type        = string
}
variable "accepter_route_table_id" {
  type        = string
}