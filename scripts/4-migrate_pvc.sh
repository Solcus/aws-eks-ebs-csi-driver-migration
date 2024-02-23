#!/usr/bin/env bash

# This script migrates a PVC from in-tree driver to CSI driver for AWS EBS volumes.

# SET global variables
NAMESPACE=$1 
PVC_NAME=$2

# CHECK user inputs
if [ -z "$PVC_NAME" ]; then
  echo "No PVC name provided"
  exit 1
fi

if [ -z "$NAMESPACE" ]; then
  NAMESPACE=default
fi

# GET Volume information
VOLUME_NAME=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}')
VOLUME_ID=$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.awsElasticBlockStore.volumeID}')
VOLUME_SIZE=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
VOLUME_DELETION_POLICY=$(kubectl get pv $(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')

echo "VOLUME_NAME: $VOLUME_NAME"
echo "VOLUME_ID: $VOLUME_ID"
echo "VOLUME_SIZE: $VOLUME_SIZE"
echo "VOLUME_DELETION_POLICY: $VOLUME_DELETION_POLICY"

# CREATE a snapshot of the volume
create_snapshot() {
  SNAPSHOT=$(aws ec2 create-snapshot \
    --volume-id $VOLUME_ID \
    --description "Migration snapshot of PVC $PVC_NAME in namespace $NAMESPACE" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$snapshot_prefix$PVC_NAME},{Key=Namespace,Value=$NAMESPACE},{Key=Migration,Value=true}]" \
    --output json)
}

# # CREATE a snapshot of the volume
create_snapshot

# CHECK if snapshot creation was successful, by checking snapshotId
if [ -z "$SNAPSHOT" ]; then
  echo "Snapshot creation failed"
  exit 1
else 
  SNAPSHOT_ID=$(echo $SNAPSHOT | jq -r '.SnapshotId')
  echo "Snapshot ID: $SNAPSHOT_ID"
fi

for i in {1..30}; do
  SNAPSHOT_STATUS=$(aws ec2 describe-snapshots \
    --snapshot-ids $SNAPSHOT_ID \
    --output json \
    --query Snapshots[0].State)

  if [ "$SNAPSHOT_STATUS" == "\"completed\"" ]; then
    echo "Snapshot created successfully: $SNAPSHOT_ID"
    break
  elif [ "$SNAPSHOT_STATUS" == "\"pending\"" ]; then
    echo "Snapshot creation in progress, waiting for 10 seconds..."
    sleep 10
  elif [ "$SNAPSHOT_STATUS" == "\"error\"" ]; then
    echo "Snapshot creation failed"
    exit 1
  else
    echo "Snapshot creation status: $SNAPSHOT_STATUS ..."
  fi

done

# CREATE VolumeSnapshotContent
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: $PVC_NAME-snapshot-content
spec:
  volumeSnapshotRef:
    kind: VolumeSnapshot
    name: $PVC_NAME-snapshot
    namespace: $NAMESPACE
  source:
    snapshotHandle: $SNAPSHOT_ID
  driver: $NEW_CSI_DRIVER
  deletionPolicy: $VOLUME_DELETION_POLICY
  volumeSnapshotClassName: $NEW_SNAPSHOT_CLASS
EOF

# CREATE VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $PVC_NAME-snapshot
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: $NEW_SNAPSHOT_CLASS
  source:
    volumeSnapshotContentName: $PVC_NAME-snapshot-content
EOF



# REMOVE the old PVC
kubectl delete pvc $PVC_NAME -n $NAMESPACE &

# Test if the PVC is deleted
for i in {1..30}; do
  PVC_STATUS=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
  if [ -z "$PVC_STATUS" ]; then
    echo "Old PVC deleted successfully"
    break
  else
    echo "PVC deletion in progress, waiting for 2 seconds..."
    echo "PVC status: $PVC_STATUS"
    kubectl patch pvc $PVC_NAME -n $NAMESPACE -p '{"metadata":{"finalizers": []}}' --type=merge
    sleep 2
  fi
done

# CREATE PVC with the new storage class
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: $NEW_STORAGE_CLASS
  resources:
    requests:
      storage: $VOLUME_SIZE
  dataSource:
    name: $PVC_NAME-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# Remove old PV
kubectl delete pv $VOLUME_NAME &

# Test if the PV is deleted
for i in {1..30}; do
  PV_STATUS=$(kubectl get pv $VOLUME_NAME -o jsonpath='{.status.phase}')
  if [ -z "$PV_STATUS" ]; then
    echo "Old PV deleted successfully"
    break
  else
    echo "PV deletion in progress, waiting for 2 seconds..."
    echo "PV status: $PV_STATUS"
    kubectl patch pv $VOLUME_NAME -p '{"metadata":{"finalizers": []}}' --type=merge
    sleep 2
  fi
done