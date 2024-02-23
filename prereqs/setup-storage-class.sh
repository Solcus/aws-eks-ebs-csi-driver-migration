#!/usr/bin/env bash

# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $NEW_STORAGE_CLASS
provisioner: $NEW_CSI_DRIVER
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF