initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:${plugin_aws_version}
    imagePullPolicy: IfNotPresent
    volumeMounts:
      - mountPath: /target
        name: plugins

credentials:
  useSecret: false

serviceAccount:
  server:
    create: true
    name: velero

configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: ${backup_bucket_name}
      default: true
      config:
        region: ${aws_region}
  volumeSnapshotLocation:
    - name: default
      provider: aws
      config:
        region: ${aws_region}

schedules:
  daily-backup:
    schedule: "${backup_schedule}"
    template:
      ttl: "${backup_ttl}"
      includedNamespaces:
        - "*"
      excludedNamespaces:
        - kube-system
        - kube-public
        - kube-node-lease
        - velero

resources:
  requests:
    cpu: 500m
    memory: 256Mi
  limits:
    cpu: 1
    memory: 512Mi

nodeSelector:
  nodegroup: ${node_group_name}

tolerations:
  - operator: Exists

deployNodeAgent: true

nodeAgent:
  tolerations:
    - operator: Exists
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi
