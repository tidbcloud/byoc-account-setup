# TiDB Cloud BYOC Account Setup

## Repository Background
<!--cla-->
[TiDB Cloud](https://www.pingcap.com/tidb-cloud/) is a fully managed cloud database service (SaaS) provided by PingCAP.
To meet the needs of customers with higher data sovereignty and compliance requirements, PingCAP has introduced the **TiDB Cloud BYOC (Bring Your Own Cloud)** model.

In this model, the **Control Plane** of TiDB Cloud is managed by PingCAP, while the **Data Plane** is fully deployed within the customer's own cloud environment.
This design allows customers to enjoy the convenience of TiDB Cloud’s managed capabilities while retaining complete control over their data assets.

> Note: The terms *Control Plane* and *Data Plane* follow the architectural concepts officially described in the [PingCAP documentation](https://www.pingcap.com/article/bring-your-own-cloud-explained-simply-for-everyone/).

Under the BYOC model, customers need to deploy and configure several foundational components within their own cloud environment (such as bastion hosts, IAM roles, and optional security validation scripts).
To simplify the deployment process and ensure consistency, PingCAP centrally maintains these deployment scripts and documentation in this repository.

---

## Project Overview

This repository provides initialization and configuration scripts required to be executed on the customer side under the TiDB Cloud BYOC model.
It helps customers quickly and securely complete the preparation work for connecting the TiDB Cloud Data Plane.

---

## Repository Structure

```
byoc-account-setup/
│
├── bastion/                # Bastion host deployment scripts and documentation
├── iam_roles/              # IAM role creation scripts and policies
└── aws_sec_conf_check/     # Optional AWS environment security validation tools
```

---

## Directory Details

### 1. `bastion`

**Purpose:**
Deploy the bastion host required for the TiDB Cloud BYOC environment.

This directory contains Terraform scripts and detailed documentation (see the README in this directory) for automatically deploying the bastion EC2 instance within the customer’s AWS environment.

**Main Functions:**
- Provide PingCAP with a secure and controlled access path.
- Enable security auditing and access control.
- Allow customers to manage connections through AWS SSM after deployment.

**Customer Actions:**
Follow the instructions in `bastion/README` to execute the Terraform scripts within your AWS account and complete the bastion host deployment.
After deployment, provide the output details to the PingCAP Support Team.

---

### 2. `iam_roles`

**Purpose:**
Help customers pre-create the minimal IAM roles required for running the TiDB Cloud Data Plane.
These roles and policies are necessary for creating and configuring BYOC Data Plane components, Observability (O11y) tools, and initial deployment permissions.

**Customer Actions:**
Follow the instructions in `iam_roles/README` to deploy and configure the required IAM roles and policies in your AWS account.
Once deployed, these roles allow the TiDB Cloud Data Plane and related components to operate securely within your environment.

---

### 3. `aws_sec_conf_check`

**Purpose:**
Provide an optional set of scripts for checking the security configuration of the customer's AWS environment.

**Functions include:**
- Reviewing IAM permission boundaries and security group rules.
- Validating encryption and audit log settings.
- Detecting common security risks.

These scripts are entirely optional and serve as a reference for security best practices.
Customers may choose to run them as needed to ensure their AWS environment meets security requirements.
For detailed usage instructions, refer to the `aws_sec_conf_check/README`.

---

## Prerequisites

Before using any script in this repository, ensure that:

1. You have the necessary IAM permissions to operate within your own AWS environment.
2. [Terraform](https://developer.hashicorp.com/terraform/downloads) and [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) are installed and properly configured.
3. You have obtained the relevant contact information for technical support from the TiDB Cloud Support Team.

---

## Security Notes

- **Principle of Least Privilege:**
  Validate all scripts in an isolated testing workspace before running them in production.

- **Credential Protection:**
  Do not store sensitive variables (e.g., `auth_key`, `tenant_id`) in plaintext or in any public repositories.

- **Logging and Auditing:**
  After the bastion host is deployed, logs will automatically be forwarded to a dedicated AWS CloudWatch log group for audit and monitoring purposes.

---


Copyright 2025 PingCAP, Inc.
