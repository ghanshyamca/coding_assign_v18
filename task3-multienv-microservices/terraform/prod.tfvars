# NOTE: per-environment sizing (node type, min/max, CIDR, NAT strategy) is
# driven by locals.env_config keyed on terraform.workspace in main.tf — NOT by
# these var files. The tfvars carry only the settings that are identical across
# environments; override here if an env ever needs a different region/version.
aws_region         = "ap-south-1"
base_name          = "microsvc"
kubernetes_version = "1.33"
services           = ["api-gateway", "orders"]
