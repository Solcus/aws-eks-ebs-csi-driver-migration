#!/usr/bin/env bash

# Create SnaphotClass
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: aws-ebs-snapshot
driver: ebs.csi.aws.com
deletionPolicy: Delete
EOF