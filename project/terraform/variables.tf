variable "aws_region" {
  description = "AWS region where the ephemeral EKS cluster will be created."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Keep it unique per active run/account/region."
  type        = string
  default     = "eks-cost-poc"
}

variable "run_id" {
  description = "Experiment run identifier used for tagging and result correlation."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project tag applied to created AWS resources."
  type        = string
  default     = "eks-poc"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version in standard support."
  type        = string
  default     = "1.37"
}

variable "node_instance_type" {
  description = "EC2 instance type for the initial managed node group."
  type        = string
  default     = "t3.medium"
}

variable "cluster_size" {
  description = "Node count preset for the POC cluster. Use small, medium, or large."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.cluster_size)
    error_message = "cluster_size must be one of: small, medium, large."
  }
}

variable "min_node_count" {
  description = "Optional minimum node count override. Leave null to use cluster_size."
  type        = number
  default     = null

  validation {
    condition     = var.min_node_count == null || var.min_node_count >= 1
    error_message = "min_node_count must be null or at least 1."
  }
}

variable "max_node_count" {
  description = "Optional maximum node count override. Leave null to use cluster_size."
  type        = number
  default     = null

  validation {
    condition     = var.max_node_count == null || var.max_node_count <= 10
    error_message = "max_node_count must be null or no larger than 10."
  }
}

variable "node_capacity_type" {
  description = "Managed node group capacity type. ON_DEMAND is more reproducible; SPOT is cheaper but less stable."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "workload_level" {
  description = "Default workload level recorded as metadata for a run: light, medium, or heavy."
  type        = string
  default     = "light"

  validation {
    condition     = contains(["light", "medium", "heavy"], var.workload_level)
    error_message = "workload_level must be one of: light, medium, heavy."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Restrict this to your current public IP for real runs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
