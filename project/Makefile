TF_DIR := terraform
TF_PLAN := tfplan

.PHONY: init plan apply destroy kubeconfig workload-light workload-medium workload-heavy clean-workloads clean-plan

init:
	terraform -chdir=$(TF_DIR) init

plan:
	terraform -chdir=$(TF_DIR) plan -out=$(TF_PLAN)

apply:
	terraform -chdir=$(TF_DIR) apply $(TF_PLAN)

destroy:
	terraform -chdir=$(TF_DIR) destroy

kubeconfig:
	aws eks update-kubeconfig --region "$$(terraform -chdir=$(TF_DIR) output -raw aws_region)" --name "$$(terraform -chdir=$(TF_DIR) output -raw cluster_name)"

workload-light:
	LEVEL=light RUN_ID="$$(terraform -chdir=$(TF_DIR) output -raw run_id)" MAX_NODE_COUNT="$$(terraform -chdir=$(TF_DIR) output -raw max_node_count)" ./scripts/run-workload.sh

workload-medium:
	LEVEL=medium RUN_ID="$$(terraform -chdir=$(TF_DIR) output -raw run_id)" MAX_NODE_COUNT="$$(terraform -chdir=$(TF_DIR) output -raw max_node_count)" ./scripts/run-workload.sh

workload-heavy:
	LEVEL=heavy RUN_ID="$$(terraform -chdir=$(TF_DIR) output -raw run_id)" MAX_NODE_COUNT="$$(terraform -chdir=$(TF_DIR) output -raw max_node_count)" ./scripts/run-workload.sh

clean-workloads:
	kubectl delete namespace eks-poc --ignore-not-found=true

clean-plan:
	rm -f $(TF_DIR)/$(TF_PLAN)
