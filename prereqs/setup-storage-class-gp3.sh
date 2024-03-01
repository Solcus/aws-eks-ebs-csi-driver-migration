#!/usr/bin/env bash

echo ">> Creating StorageClass for gp3 volumes"
echo "!! Only use this SC if your instances are suitable for GP3 volumes !!"

echo "Press [Enter] to confirm..." && read

# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aws-ebs-gp3
  # annotations:
  #   storageclass.kubernetes.io/is-default-class: "true"
allowVolumeExpansion: true
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
EOF