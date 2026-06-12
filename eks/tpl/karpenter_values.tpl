serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${iam_role_arn}
imagePullPolicy: Always
podDisruptionBudget:
  maxUnavailable: 1
replicas: 2
nodeSelector:
  nodegroup: ${node_group_name}
tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "${node_group_role}"
    effect: "NoSchedule"
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: karpenter
controller:
  resources:
    requests:
      cpu: 1
      memory: 1Gi
    limits:
      cpu: 1
      memory: 1Gi
settings:
  clusterName: ${cluster_name}
  clusterEndpoint: ${cluster_endpoint}
  interruptionQueue: ${queue_name}
  featureGates:
    drift: true
    spotToSpotConsolidation: true