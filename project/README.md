# EKS POC

Minimal proof of concept for a local Terraform workflow:

1. Create a small Amazon EKS cluster.
2. Run bounded Kubernetes workloads.
3. Save basic run measurements.
4. Destroy the AWS resources.

No Terraform modules are used. The only Terraform provider is `hashicorp/aws`.

## Repository

```text
terraform/                 Terraform config for AWS/EKS
k8s/                       Kubernetes namespace and workload template
scripts/run-workload.sh    Renders, runs, and measures one workload
Makefile                   Short commands for init/plan/apply/destroy
results/                   Created by workload runs and ignored by git
```

## Infrastructure

Terraform creates:

- one VPC;
- one internet gateway;
- two public subnets;
- one EKS cluster;
- one EKS managed node group;
- IAM roles and policy attachments required by EKS and the worker nodes.

The worker nodes run in public subnets to keep the POC simple and avoid NAT gateway charges. This is a cost-conscious experiment setup, not a production network design.

## Prerequisites

- AWS CLI configured locally.
- Terraform installed.
- `kubectl` installed.
- AWS permissions for EKS, EC2, IAM, VPC, and Auto Scaling resources.

Do not commit AWS credentials or secrets.

## Configure

Create a local variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
aws_region     = "eu-central-1"
cluster_name   = "eks-cost-poc"
run_id         = "run-001"
project_name   = "eks-poc"
workload_level = "light"

node_instance_type = "t3.medium"
min_node_count     = 1
max_node_count     = 3
node_capacity_type = "ON_DEMAND"
```

Optional but recommended: restrict the Kubernetes API endpoint CIDR:

```hcl
cluster_endpoint_public_access_cidrs = ["YOUR_PUBLIC_IP/32"]
```

## Terraform Workflow

These commands create billable AWS resources. Run `apply` only when you intend to create the cluster.

```bash
make init
make plan
make apply
```

Configure `kubectl` after apply:

```bash
make kubeconfig
```

Destroy the Terraform-managed AWS resources:

```bash
make destroy
```

Raw equivalents:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
terraform -chdir=terraform destroy
```

## Workloads

Run one workload after the cluster is created and `kubectl` is configured:

```bash
make workload-light
make workload-medium
make workload-heavy
```

The workload script creates namespace `eks-poc`, renders `k8s/workload-job.yaml.tpl`, applies a Kubernetes Job, samples cluster state, and writes results under:

```text
results/<run_id>/<level>/
```

Generated artifacts include:

- `result.json`
- `samples.csv`
- rendered `workload.yaml`
- final Job and Pod snapshots
- Kubernetes event snapshots
- `kubectl top` snapshots when metrics are available

The workloads are bounded by active deadlines and explicit CPU/memory requests and limits. Defaults:

| Level | Replicas | CPU request/limit | Memory request/limit | Max duration |
| --- | ---: | --- | --- | ---: |
| `light` | 1 | `250m` / `500m` | `160Mi` / `256Mi` | 90s |
| `medium` | 4 | `500m` / `1000m` | `320Mi` / `512Mi` | 180s |
| `heavy` | 8 | `1000m` / `2000m` | `640Mi` / `1024Mi` | 300s |

`RUN_ID` is normalized by the script to lowercase Kubernetes-safe characters. For example, `Run_001` becomes `run-001`.

Delete workload objects:

```bash
make clean-workloads
```

## Local State

Terraform state is local:

```text
terraform/terraform.tfstate
```

This repo allows local state files. Treat state as sensitive because it can contain AWS resource identifiers and provider metadata. Do not publish it.

Also review `terraform/terraform.tfvars` before sharing the repository. It should not contain credentials, but it may contain account-specific settings such as regions, names, and IP allowlists.

## Cost Notes

This POC can incur AWS charges for:

- EKS control plane runtime;
- EC2 worker nodes;
- EBS root volumes;
- data transfer.

This simplified version avoids NAT gateway and Elastic IP charges. Always run `make destroy` when finished, then check the AWS console for leftover EKS, EC2, EBS, VPC, load balancer, or CloudWatch resources.

## Current Limits

- No node autoscaler is installed yet.
- No metrics-server is installed by Terraform.
- Workload measurements are basic local artifacts, not a full benchmark harness.
- Public worker subnets are used for simplicity.
