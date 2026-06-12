#!/usr/bin/env bash
# Applies the EC2NodeClass/NodePool manifests under tpl/*.yaml to the EKS
# cluster created by this module. Run after `terraform apply` so the
# cluster and Karpenter CRDs already exist.
#
# Usage: scripts/apply-karpenter-manifests.sh <var-file.json>
set -euo pipefail

VAR_FILE="$1"

CLUSTER_NAME=$(jq -r .cluster_name "$VAR_FILE")
AWS_REGION=$(jq -r .aws_region "$VAR_FILE")
AWS_ACCOUNT_ID=$(jq -r .aws_account_id "$VAR_FILE")
AWS_ASSUME_ROLE=$(jq -r .aws_assume_role "$VAR_FILE")

aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ASSUME_ROLE}"

export CLUSTER_NAME
export KARPENTER_ROLE="$(terraform output -raw karpenter_node_iam_role_name)"

for f in tpl/*.yaml; do
  envsubst '${KARPENTER_ROLE} ${CLUSTER_NAME}' < "$f" | kubectl apply -f -
done
