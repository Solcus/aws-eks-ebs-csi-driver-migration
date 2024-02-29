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
# VOLUME_ID=$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.awsElasticBlockStore.volumeID}')

# If the olddriver is kubernetes.io/aws-ebs, then the volumeID is in awsElasticBlockStore.volumeID
# If the olddriver is ebs.csi.aws.com, then the volumeID is in csi.volumeHandle
if [[ "$OLD_CSI_DRIVER" == "kubernetes.io/aws-ebs" ]]; then
  VOLUME_ID="vol-$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' | awk -F'vol-' '{print $2}')"
elif [[ "$OLD_CSI_DRIVER" == "ebs.csi.aws.com" ]]; then
  VOLUME_ID="vol-$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.csi.volumeHandle}' | awk -F'vol-' '{print $2}')"
fi

# VOLUME_ID="vol-$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' | awk -F'vol-' '{print $2}')"
VOLUME_SIZE=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
VOLUME_DELETION_POLICY=$(kubectl get pv $(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')



echo "NAMESPACE: $NAMESPACE"
echo "PVC_NAME: $PVC_NAME"
echo "VOLUME_NAME: $VOLUME_NAME"
echo "VOLUME_ID: $VOLUME_ID"
echo "VOLUME_SIZE: $VOLUME_SIZE"
echo "VOLUME_DELETION_POLICY: $VOLUME_DELETION_POLICY"

# [[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to create the EBS snapshot, VolumeSnapshotContent and VolumeSnapshot..." && read

[[ $DRY_RUN == "true" ]] && echo ">> DRY_RUN: Skipping snapshot creation." && exit 0

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
  echo ">> Snapshot creation failed"
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
    echo ">> Snapshot created successfully: $SNAPSHOT_ID"
    break
  elif [ "$SNAPSHOT_STATUS" == "\"pending\"" ]; then
    echo ".. Snapshot creation in progress, waiting for 10 seconds..."
    sleep 10
  elif [ "$SNAPSHOT_STATUS" == "\"error\"" ]; then
    echo ">> Snapshot creation failed"
    exit 1
  else
    echo ".. Snapshot creation status: $SNAPSHOT_STATUS ..."
  fi

done

# CREATE VolumeSnapshotContent
# cat <<EOF | kubectl apply -f -
cat <<EOF > $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: $NAMESPACE-$PVC_NAME-snapshot-content
spec:
  volumeSnapshotRef:
    kind: VolumeSnapshot
    name: $NAMESPACE-$PVC_NAME-snapshot
    namespace: $NAMESPACE
  source:
    snapshotHandle: $SNAPSHOT_ID
  driver: $NEW_CSI_DRIVER
  deletionPolicy: $VOLUME_DELETION_POLICY
  volumeSnapshotClassName: $NEW_SNAPSHOT_CLASS
EOF

# CREATE VolumeSnapshot
# cat <<EOF | kubectl apply -f -
cat <<EOF > $runtime_folder/tmp_vs_${PVC_NAME}.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $NAMESPACE-$PVC_NAME-snapshot
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: $NEW_SNAPSHOT_CLASS
  source:
    volumeSnapshotContentName: $NAMESPACE-$PVC_NAME-snapshot-content
EOF

if [ "$DRY_RUN" != "false" ]; then
  echo ">> DRY_RUN: Skipping VolumeSnapshotContent and VolumeSnapshot creation"
  cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
  cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml
else
  kubectl apply -f $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
  kubectl apply -f $runtime_folder/tmp_vs_${PVC_NAME}.yaml
fi

echo ">> Checking if VolumeSnapshotContent and VolumeSnapshot are ready..."
VS_READY="false"
sleep 3

for i in {1..12}; do
  [[ $DRY_RUN != "false" ]] && break

  VSC_STATUS=$(kubectl get volumesnapshotcontent $NAMESPACE-$PVC_NAME-snapshot-content -n $NAMESPACE -o jsonpath='{.status.readyToUse}')
  VS_STATUS=$(kubectl get volumesnapshot $NAMESPACE-$PVC_NAME-snapshot -n $NAMESPACE -o jsonpath='{.status.readyToUse}')

  if [ "$VSC_STATUS" == "true" ] && [ "$VS_STATUS" == "true" ]; then
    echo ">> VolumeSnapshotContent and VolumeSnapshot are ready"
    VS_READY="true"
    break
  else
    echo ".. VolumeSnapshotContent and VolumeSnapshot are not ready... Waiting for 5 seconds..."
    sleep 5
  fi

done

echo "SNAPSHOT_ID: $SNAPSHOT_ID"
echo "VSC_STATUS: $VSC_STATUS"
echo "VS_STATUS: $VS_STATUS"

if [ "$VS_READY" != "true" ]; then
  if [ "$DRY_RUN" != "false" ]; then
    echo "!! VolumeSnapshotContent and VolumeSnapshot are not ready because of DRYRUN. Contents:"
    cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
    echo
    cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml
  else
    echo "!! VolumeSnapshotContent and VolumeSnapshot are not ready... Skipping PVC migration. Debug:"
    cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
    cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml
    exit 1
  fi
fi

# [[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to set the PV reclaim policy to Retain..." && read

# Set volume to Retain
if [ "$DRY_RUN" != "false" ]; then
  echo ">> DRY_RUN: Skipping PV reclaim policy update"
else
  kubectl patch pv $VOLUME_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
fi

# [[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to replace the PVC and PV..." && read

# REMOVE the old PVC
kubectl delete pvc $PVC_NAME -n $NAMESPACE &

set +e

# Test if the PVC is deleted
for i in {1..30}; do
  PVC_STATUS=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
  if [ -z "$PVC_STATUS" ]; then
    echo ">> Old PVC deleted successfully"
    break
  else
    echo ".. PVC deletion in progress, waiting for 2 seconds..."
    echo ".. PVC status: $PVC_STATUS"
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
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: $NEW_STORAGE_CLASS
  resources:
    requests:
      storage: $VOLUME_SIZE
  dataSource:
    name: $NAMESPACE-$PVC_NAME-snapshot
    kind: VolumeSnapshot
    apiGroup: $vsc_api_version
EOF

# Remove old PV
kubectl delete pv $VOLUME_NAME &

# Test if the PV is deleted
for i in {1..30}; do
  PV_STATUS=$(kubectl get pv $VOLUME_NAME -o jsonpath='{.status.phase}')
  if [ -z "$PV_STATUS" ]; then
    echo ">> Old PV deleted successfully"
    break
  else
    echo ".. PV deletion in progress, waiting for 2 seconds..."
    echo ".. PV status: $PV_STATUS"
    kubectl patch pv $VOLUME_NAME -p '{"metadata":{"finalizers": []}}' --type=merge
    sleep 2
  fi
done

set -e

# Get all pods that use the PVC
echo ">> Checking for pods that are using the PVC"
AFFECTED_PODS=$(kubectl get pods -n $NAMESPACE -o=jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}{end}' | grep $PVC_NAME | awk '{print $2}')
AMOUNT_OF_PODS=$(echo "$AFFECTED_PODS" | wc -l)

if [ -z "$AFFECTED_PODS" ]; then
  echo ">> No pods found using the PVC"
else
  echo ">> Affected pods:" && echo "$AFFECTED_PODS"

  for pod in $AFFECTED_PODS; do
    echo ">> Restarting pod '$pod' in namespace '$NAMESPACE' to use the new PVC... (RollingUpdate)"

    kubectl delete pod $pod -n $NAMESPACE &

    echo ".. Waiting for new pod to be created..."
    sleep 10

    NEW_POD=$(kubectl get pods --namespace $NAMESPACE --sort-by=.metadata.creationTimestamp -o json | jq -r '.items | last(.[]) | .metadata.name')
    NEW_POD_PVC=$(kubectl get pod $NEW_POD -n $NAMESPACE -o=jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}')

    if [[ "$NEW_POD_PVC" == "$PVC_NAME" ]]; then
      echo ">> New pod '$NEW_POD' is using the correct PVC: $NEW_POD_PVC"
    else
      echo "!! New Pod has not been created yet."
      echo "!! Latest pod: $NEW_POD"
      echo "!! Latest pod PVC: $NEW_POD_PVC"
      exit 1
    fi
    
    kubectl wait --for=condition=ready pod $NEW_POD -n $NAMESPACE --timeout=300s

    echo ">> Pod '$NEW_POD' is running"

  done

fi

# DETACH old volume from the node instance
echo ">> Detaching old volume from the node instance..."
if [[ $DRY_RUN == "false" ]]; then
    sleep 5
    aws ec2 detach-volume --volume-id $VOLUME_ID | jq
    # aws ec2 wait volume-available --volume-ids $VOLUME_ID
else 
    set +e
    aws ec2 detach-volume --volume-id $VOLUME_ID --dry-run
    set -e
fi


echo ">> Migration of PVC $PVC_NAME in namespace $NAMESPACE is complete."
echo 




