output "dataops_account_id" {
  value = data.aws_caller_identity.dataops.account_id
}

# output "rds_account_id" {
#   value = data.aws_caller_identity.rds.account_id
# }