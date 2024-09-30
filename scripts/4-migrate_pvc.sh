#!/usr/bin/env bash

# This script migrates a PVC from in-tree driver to CSI driver for AWS EBS volumes.

# SET global variables
NAMESPACE=$1 
PVC_NAME=$2
MIGRATION_TIMESTAMP=$(date +'%Y%m%d%H%M%S')
# CHECK user inputs
if [ -z "$PVC_NAME" ]; then
  echo "$(date +'%H:%M:%S') No PVC name provided"
  exit 1
fi

if [ -z "$NAMESPACE" ]; then
  NAMESPACE=default
fi

# GET Volume information
VOLUME_NAME=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}')

# GET the volume ID based on the CSI driver type
if [[ "$OLD_CSI_DRIVER" == "kubernetes.io/aws-ebs" ]]; then
  VOLUME_ID="vol-$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' | awk -F'vol-' '{print $2}')"
elif [[ "$OLD_CSI_DRIVER" == "ebs.csi.aws.com" ]]; then
  VOLUME_ID="vol-$(kubectl get pv $VOLUME_NAME -o jsonpath='{.spec.csi.volumeHandle}' | awk -F'vol-' '{print $2}')"
fi

VOLUME_SIZE=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
VOLUME_DELETION_POLICY=$(kubectl get pv $(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')

# Get all pods that use the PVC
echo "$(date +'%H:%M:%S') >> Checking for pods that are using the PVC"
AFFECTED_PODS=$(kubectl get pods -n $NAMESPACE -o=jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}{end}' | grep $PVC_NAME | awk '{print $2}')
if [ -z "$AFFECTED_PODS" ]; then
  AMOUNT_OF_PODS=0
else
  AMOUNT_OF_PODS=$(echo $AFFECTED_PODS | wc -l)
fi

cat <<EOF > $backup_folder/$NAMESPACE-$PVC_NAME.dump
MIGRATION_TIMESTAMP    : $MIGRATION_TIMESTAMP
NAMESPACE              : $NAMESPACE
PVC_NAME               : $PVC_NAME
OLD_VOLUME_NAME        : $VOLUME_NAME
OLD_VOLUME_ID          : $VOLUME_ID
VOLUME_SIZE            : $VOLUME_SIZE
VOLUME_DELETION_POLICY : $VOLUME_DELETION_POLICY
AFFECTED_PODS          : $AFFECTED_PODS
AMOUNT_OF_PODS         : $AMOUNT_OF_PODS
EOF

cat $backup_folder/$NAMESPACE-$PVC_NAME.dump

# [[ $DRY_RUN == "true" ]] && echo "$(date +'%H:%M:%S') >> DRY_RUN: Skipping snapshot creation." && exit 0

# CREATE a snapshot of the volume
create_snapshot() {
  SNAPSHOT=$(aws ec2 create-snapshot \
    --volume-id $VOLUME_ID \
    --description "Migration snapshot of PVC $PVC_NAME in namespace $NAMESPACE" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key="ec2:ResourceTag/ebs.csi.aws.com/cluster",Value="true"}]" \
    --output json $dry_run_flag)
}

# # CREATE a snapshot of the volume
create_snapshot

# CHECK if snapshot creation was successful, by checking snapshotId
if [ -z "$SNAPSHOT" ]; then
  echo "$(date +'%H:%M:%S') >> Snapshot creation failed"
  exit 1
else 
  SNAPSHOT_ID=$(echo $SNAPSHOT | jq -r '.SnapshotId')
  echo "SNAPSHOT ID            : $SNAPSHOT_ID"
fi

for i in {1..30}; do
  SNAPSHOT_STATUS=$(aws ec2 describe-snapshots \
    --snapshot-ids $SNAPSHOT_ID \
    --output json \
    --query Snapshots[0].State)

  if [ "$SNAPSHOT_STATUS" == "\"completed\"" ]; then
    aws ec2 describe-snapshots --snapshot-ids $SNAPSHOT_ID --output json | jq
    echo "$(date +'%H:%M:%S') >> Snapshot created successfully: $SNAPSHOT_ID"
    break
  elif [ "$SNAPSHOT_STATUS" == "\"pending\"" ]; then
    echo "$(date +'%H:%M:%S') .. Snapshot creation in progress, waiting for 10 seconds..."
    sleep 10
  elif [ "$SNAPSHOT_STATUS" == "\"error\"" ]; then
    echo "$(date +'%H:%M:%S') >> Snapshot creation failed"
    exit 1
  else
    echo "$(date +'%H:%M:%S') .. Snapshot creation status: $SNAPSHOT_STATUS ..."
  fi

done

# CREATE VolumeSnapshotContent
cat <<EOF > $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotContent
metadata:
  name: $NAMESPACE-$PVC_NAME-snapshot-content-$MIGRATION_TIMESTAMP
spec:
  volumeSnapshotRef:
    kind: VolumeSnapshot
    name: $NAMESPACE-$PVC_NAME-snapshot-$MIGRATION_TIMESTAMP
    namespace: $NAMESPACE
  source:
    snapshotHandle: $SNAPSHOT_ID
  driver: $NEW_CSI_DRIVER
  deletionPolicy: $VOLUME_DELETION_POLICY
  volumeSnapshotClassName: $NEW_SNAPSHOT_CLASS
EOF

# CREATE VolumeSnapshot
cat <<EOF > $runtime_folder/tmp_vs_${PVC_NAME}.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $NAMESPACE-$PVC_NAME-snapshot-$MIGRATION_TIMESTAMP
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: $NEW_SNAPSHOT_CLASS
  source:
    volumeSnapshotContentName: $NAMESPACE-$PVC_NAME-snapshot-content-$MIGRATION_TIMESTAMP
EOF

cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml >> $backup_folder/$NAMESPACE-$PVC_NAME.dump
cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml >> $backup_folder/$NAMESPACE-$PVC_NAME.dump

if [ "$DRY_RUN" != "false" ]; then
  echo "$(date +'%H:%M:%S') >> DRY_RUN: Skipping VolumeSnapshotContent and VolumeSnapshot creation"
  cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
  cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml
else
  kubectl apply -f $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
  kubectl apply -f $runtime_folder/tmp_vs_${PVC_NAME}.yaml
fi

echo "$(date +'%H:%M:%S') >> Checking if VolumeSnapshotContent and VolumeSnapshot are ready..."
VS_READY="false"
sleep 3

for i in {1..90}; do
  [[ $DRY_RUN != "false" ]] && break

  VSC_STATUS=$(kubectl get volumesnapshotcontent $NAMESPACE-$PVC_NAME-snapshot-content-$MIGRATION_TIMESTAMP -n $NAMESPACE -o jsonpath='{.status.readyToUse}')
  VS_STATUS=$(kubectl get volumesnapshot $NAMESPACE-$PVC_NAME-snapshot-$MIGRATION_TIMESTAMP -n $NAMESPACE -o jsonpath='{.status.readyToUse}')

  if [ "$VSC_STATUS" == "true" ] && [ "$VS_STATUS" == "true" ]; then
    echo "$(date +'%H:%M:%S') >> VolumeSnapshotContent and VolumeSnapshot are ready"
    VS_READY="true"
    break
  else
    echo "$(date +'%H:%M:%S') .. VolumeSnapshotContent and VolumeSnapshot are not ready... Waiting for 30 seconds..."
    sleep 30
  fi

done

cat <<EOF >> $backup_folder/$NAMESPACE-$PVC_NAME.dump
SNAPSHOT_ID            : $SNAPSHOT_ID
VSC_NAME               : $NAMESPACE-$PVC_NAME-snapshot-content-$MIGRATION_TIMESTAMP
VS_NAME                : $NAMESPACE-$PVC_NAME-snapshot-$MIGRATION_TIMESTAMP
VSC_STATUS             : $VSC_STATUS
VS_STATUS              : $VS_STATUS
VS_READY               : $VS_READY
EOF

cat $backup_folder/$NAMESPACE-$PVC_NAME.dump | tail -n 3

if [ "$VS_READY" != "true" ]; then
  if [ "$DRY_RUN" != "false" ]; then
    echo "$(date +'%H:%M:%S') !! VolumeSnapshotContent and VolumeSnapshot are not ready because of DRYRUN. Contents:"
    cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
    echo
    cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml
  else
    echo "$(date +'%H:%M:%S') !! VolumeSnapshotContent and VolumeSnapshot are not ready... Skipping PVC migration. Debug:"
    cat $runtime_folder/tmp_vsc_${PVC_NAME}.yaml
    cat $runtime_folder/tmp_vs_${PVC_NAME}.yaml
    exit 1
  fi
fi

# Set volume to Retain
if [ "$DRY_RUN" != "false" ]; then
  echo "$(date +'%H:%M:%S') >> DRY_RUN: Skipping PV reclaim policy update"
else
  kubectl patch pv $VOLUME_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
  sleep 5
fi

# REMOVE the old PVC
kubectl delete pvc $PVC_NAME -n $NAMESPACE &

set +e
kubectl patch pvc $PVC_NAME -n $NAMESPACE -p '{"metadata":{"finalizers": []}}' --type=merge

# Test if the PVC is deleted
for i in {1..30}; do
  PVC_STATUS=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
  if [ -z "$PVC_STATUS" ]; then
    echo "$(date +'%H:%M:%S') >> Old PVC deleted successfully"
    break
  else
    echo "$(date +'%H:%M:%S') .. PVC deletion in progress, waiting for 2 seconds..."
    echo "$(date +'%H:%M:%S') .. PVC status: $PVC_STATUS"
    kubectl patch pvc $PVC_NAME -n $NAMESPACE -p '{"metadata":{"finalizers": []}}' --type=merge
    sleep 2
  fi
done

# CREATE PVC with the new storage class
cat <<EOF > $runtime_folder/tmp_pvc_${PVC_NAME}.yaml
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
    name: $NAMESPACE-$PVC_NAME-snapshot-$MIGRATION_TIMESTAMP
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

cat $runtime_folder/tmp_pvc_${PVC_NAME}.yaml >> $backup_folder/$NAMESPACE-$PVC_NAME.dump
kubectl apply -f $runtime_folder/tmp_pvc_${PVC_NAME}.yaml

# Remove old PV
kubectl delete pv $VOLUME_NAME &

# Test if the PV is deleted
for i in {1..30}; do
  PV_STATUS=$(kubectl get pv $VOLUME_NAME -o jsonpath='{.status.phase}')
  if [ -z "$PV_STATUS" ]; then
    echo "$(date +'%H:%M:%S') >> Old PV deleted successfully"
    break
  else
    echo "$(date +'%H:%M:%S') .. PV deletion in progress, waiting for 2 seconds..."
    echo "$(date +'%H:%M:%S') .. PV status: $PV_STATUS"
    kubectl patch pv $VOLUME_NAME -p '{"metadata":{"finalizers": []}}' --type=merge
    sleep 2
  fi
done

set -e

if [[ "$POD_RECREATE" == "false" ]]; then
  echo "$(date +'%H:%M:%S') >> Skipping pod recreation..."
else
  if [ -z "$AFFECTED_PODS" ]; then
    echo "$(date +'%H:%M:%S') >> No pods found using the PVC"
  else
    echo "$(date +'%H:%M:%S') >> Affected pods:" && echo "$(date +'%H:%M:%S') $AFFECTED_PODS"

    for pod in $AFFECTED_PODS; do
      echo "$(date +'%H:%M:%S') >> Restarting pod '$pod' in namespace '$NAMESPACE' to use the new PVC... (RollingUpdate)"

      kubectl delete pod $pod -n $NAMESPACE &

      echo "$(date +'%H:%M:%S') .. Waiting for new pod to be created..."
      MAX_TIMER=300
      ACT_TIMER=0

      while true; do
        
        if [[ $ACT_TIMER -gt $MAX_TIMER ]]; then
          echo "$(date +'%H:%M:%S') !! New pod creation took too long ($MAX_TIMER s). Exiting..."
          echo "$(date +'%H:%M:%S') !! Latest pod: $NEW_POD"
          echo "$(date +'%H:%M:%S') !! Latest pod PVC: $NEW_POD_PVC"
          exit 1
        fi

        NEW_POD=$(kubectl get pods --namespace $NAMESPACE --sort-by=.metadata.creationTimestamp -o json | jq -r '.items | last(.[]) | .metadata.name')
        NEW_POD_PVC=$(kubectl get pod $NEW_POD -n $NAMESPACE -o=jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}')

        AGE=$(kubectl get pod $NEW_POD -n $NAMESPACE --no-headers | head -n 1 | awk '{print $5}')
        TIME_AMOUNT=$(echo $AGE | sed 's/[a-z]//g')
        TIME_UNIT=$(echo $AGE | sed 's/[0-9]//g')

        if [[ "$TIME_UNIT" == "s" && "$TIME_AMOUNT" -lt 15 ]]; then
            echo "$(date +'%H:%M:%S') >> New pod found: '$NEW_POD' (age: $AGE)."
            break
        else
            echo "$(date +'%H:%M:%S') .. Waiting for new pod to be created..."
            sleep 4
            ACT_TIMER=$((ACT_TIMER+4))
        fi

      done

      # NEW_POD=$(kubectl get pods --namespace $NAMESPACE --sort-by=.metadata.creationTimestamp -o json | jq -r '.items | last(.[]) | .metadata.name')
      # NEW_POD_PVC=$(kubectl get pod $NEW_POD -n $NAMESPACE -o=jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}')
            
      echo "$(date +'%H:%M:%S') NEW POD CREATED        : $NEW_POD" >> $backup_folder/$NAMESPACE-$PVC_NAME.dump

      if [[ "$NEW_POD_PVC" == "$PVC_NAME" ]]; then
        echo "$(date +'%H:%M:%S') >> New pod '$NEW_POD' is using the correct PVC: $NEW_POD_PVC"
      else
        echo "$(date +'%H:%M:%S') !! New pod '$NEW_POD' is not using the correct PVC: $NEW_POD_PVC"
        exit 1
      fi
      
      kubectl wait --for=condition=ready pod $NEW_POD -n $NAMESPACE --timeout=300s

      echo "$(date +'%H:%M:%S') >> Pod '$NEW_POD' is running"

      echo "$(date +'%H:%M:%S') NEW POD READY          : $NEW_POD" >> $backup_folder/$NAMESPACE-$PVC_NAME.dump

    done

  fi
fi

# DETACH old volume from the node instance
if [[ $cluster_scale == "true" ]]; then
    echo "$(date +'%H:%M:%S') >> Skipping detachment of old volume from the node instance..."
else
  echo "$(date +'%H:%M:%S') >> Detaching old volume from the node instance..."
  if [[ $DRY_RUN == "false" ]]; then
      sleep 5
      aws ec2 detach-volume --volume-id $VOLUME_ID | jq
  else 
      set +e
      aws ec2 detach-volume --volume-id $VOLUME_ID --dry-run
      set -e
  fi
  echo "$(date +'%H:%M:%S') VOLUME DETACHED        : $VOLUME_ID" >> $backup_folder/$NAMESPACE-$PVC_NAME.dump
fi

echo "$(date +'%H:%M:%S') >> Migration of PVC $PVC_NAME in namespace $NAMESPACE is complete."
echo 




