output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

# output "bastion_security_group_id" {
#   value = aws_security_group.bastion.id
# }

# output "bastion_security_group_name" {
#   value = aws_security_group.bastion.name
# }

# output "bastion_security_group_vpc_id" {
#   value = aws_security_group.bastion.vpc_id
# }

