# RDS

Terraform configuration that provisions an Aurora PostgreSQL cluster on top of an existing VPC. Each environment gets its own cluster, deployed into the `database` subnet tier of the matching VPC.

State is stored in S3 (see [`backend.tf`](backend.tf)).

## Architecture

- The VPC and subnets are **not** created here — they're discovered by tag from an existing VPC named `<vpc_name>-vpc`, using the subnets tagged `Tier=database` ([`data.tf`](data.tf)).
- [`rds.tf`](rds.tf) provisions:
  - An `aws_rds_cluster` (Aurora PostgreSQL), encrypted with a dedicated `aws_kms_key`.
  - `var.rds_writer_replica_count` writer instance(s) and `var.rds_reader_replica_count` reader instance(s) (`aws_rds_cluster_instance`), tagged `role=writer`/`role=reader`.
  - A random master password (`random_password`), with the master username, password, and database name written to SSM as `SecureString` parameters under `/<vpc_name>/database/...`.
  - A dedicated `aws_db_subnet_group` spanning the database subnets.
- [`sg.tf`](sg.tf) creates a security group allowing PostgreSQL (5432) ingress from within the VPC CIDR, and unrestricted egress.

## Repository layout

```
.
├── backend.tf       # S3 backend config
├── data.tf          # VPC/database-subnet discovery (by tag)
├── rds.tf           # Aurora cluster, instances, KMS key, SSM parameters, subnet group
├── sg.tf            # RDS security group
├── variable.tf
├── versions.tf      # provider: aws
└── environments/    # one *.auto.tfvars.json per environment
    ├── dev.auto.tfvars.json
    ├── qa.auto.tfvars.json
    ├── uat.auto.tfvars.json
    └── prod.auto.tfvars.json
```

## Environments

| Environment | `vpc_name` | AWS Account | Region |
|---|---|---|---|
| Development | `dev` | 891543987898 | ap-south-1 |
| QA | `qa` | 891543987898 | ap-south-1 |
| UAT | `uat` | 891543987898 | ap-south-1 |
| Production | `prod` | 891543987898 | ap-south-1 |

## Usage

```bash
terraform init
terraform workspace select <env> || terraform workspace new <env>

terraform plan  -var-file=environments/<env>.auto.tfvars.json -out=tfplan
terraform apply tfplan
```

`<env>` is the basename of a file in `environments/` (`dev`, `qa`, `uat`, `prod`).

## Variables

See [`variable.tf`](variable.tf) for full descriptions and defaults.

| Variable | Description |
|---|---|
| `aws_region` | AWS region |
| `aws_account_id` | 12-digit AWS account ID |
| `aws_assume_role` | IAM role path assumed by the provider |
| `vpc_name` | VPC/environment name; used for VPC/subnet discovery and as the environment identifier for tags, SSM paths, and resource names |
| `rds_database_name` | Name of the Aurora PostgreSQL database |
| `rds_cluster_identifier` | Prefix for the cluster identifier |
| `rds_engine` / `rds_engine_version` | Aurora engine and version |
| `rds_instance_class` | Instance class for writer/reader instances |
| `rds_writer_replica_count` / `rds_reader_replica_count` | Number of writer/reader instances |
| `rds_backup_retention_period` | Backup retention period (days) |
| `rds_auto_minor_version_upgrade` | Whether to auto-apply minor engine version upgrades |
| `rds_master_username` | Master username |

## Linting / scanning

```bash
terraform fmt -check
terraform validate
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.9
- AWS credentials able to assume `var.aws_assume_role` in the target account
- An existing VPC named `<vpc_name>-vpc` with subnets tagged `Tier=database`
