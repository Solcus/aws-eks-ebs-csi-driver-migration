#!/usr/bin/env bash

# Create SnaphotClass
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: $NEW_SNAPSHOT_CLASS
driver: $NEW_CSI_DRIVER
deletionPolicy: Delete
EOF