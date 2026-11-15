output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "aws_region" {
  description = "AWS region."
  value       = var.aws_region
}

output "run_id" {
  description = "Experiment run identifier."
  value       = var.run_id
}

output "node_instance_type" {
  description = "Managed node group instance type."
  value       = var.node_instance_type
}

output "min_node_count" {
  description = "Managed node group minimum size."
  value       = var.min_node_count
}

output "max_node_count" {
  description = "Managed node group maximum size."
  value       = var.max_node_count
}

output "kubernetes_version" {
  description = "EKS Kubernetes version."
  value       = var.kubernetes_version
}

output "configure_kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}
