#!/bin/bash

# Set the node ID
INSTANCE_ID=$1
DRY_RUN=$2

if [[ -z "$INSTANCE_ID" ]]; then
    echo "Usage: $0 <instance-id> [--dry-run]"
    exit 1
fi

echo "-  Instance ID: $INSTANCE_ID"

# List all EBS volumes attached to the node
ATTACHED_VOLUMES=$(aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" --query "Volumes[*].VolumeId" --output text)
ATTACHED_VOLUMES=$(echo "$ATTACHED_VOLUMES" | tr '  ' ' ')

echo "-  Attached Volumes: $ATTACHED_VOLUMES"

# Get all PersistentVolumes in the Kubernetes cluster
K8S_PVS=$(kubectl get pv --no-headers -o custom-columns=":spec.awsElasticBlockStore.volumeID" | awk -F'/' '{print $NF}')
K8S_PVS+=$'\n'
K8S_PVS+=$(kubectl get pv --no-headers -o custom-columns=":spec.csi.volumeHandle" | awk -F'/' '{print $NF}')

# Initialize an empty array to hold orphaned volumes
echo 
ORPHANED_VOLUMES=()

# Check each attached volume against Kubernetes PVs
for VOLUME in $ATTACHED_VOLUMES; do
    echo ".. Checking volume: $VOLUME"

    volume_name=$(aws ec2 describe-volumes --volume-ids "$VOLUME" --query "Volumes[*].Tags[?Key=='Name'].Value" --output text)
    pv_name="pvc-$(echo "$volume_name" | grep 'pvc-' | head -n 1 | awk -F'pvc-' '{print $2}')"

    if [[ "$pv_name" != "pvc-" ]]; then

        if ! echo "$K8S_PVS" | grep -qw "$VOLUME"; then
            echo "!! Potential orphaned volume."
        fi

        pv_exist=$(kubectl get pv | grep "$pv_name" | awk '{print $1}')
        pvc_exist=$(kubectl get pvc -A | grep "$pv_name" | awk '{print $2}')

        echo "-  VOLUME_NAME: $volume_name"
        echo "-  PV_NAME: $pv_name"
        echo "-  PV: $pv_exist"
        echo "-  PVC: $pvc_exist"
        
        if [[ $pv_exist == "" ]]; then
            echo "-- PV '$pv_name' - Volume $VOLUME"
        else
            echo "++ PV '$pv_name' - Volume $VOLUME"
        fi

        if [[ $pvc_exist == "" ]]; then
            echo "-- PVC for '$pv_name' - Volume $VOLUME"
        else
            echo "++ PVC '$pvc_exist' - Volume $VOLUME - PV '$pv_name'"
        fi

        if [[ $pv_exist == "" ]] && [[ $pvc_exist == "" ]]; then
            ORPHANED_VOLUMES+=("$VOLUME - $volume_name")
        fi
        echo
    fi

done

# Output the list of orphaned volumes
echo && echo ">> Orphaned Volumes (${#ORPHANED_VOLUMES[@]}):"

# Order the orphaned volumes list alphabetically
IFS=$'\n' ORPHANED_VOLUMES=($(sort <<<"${ORPHANED_VOLUMES[*]}"))
unset IFS


for ORPHAN in "${ORPHANED_VOLUMES[@]}"; do
    echo "-  $ORPHAN"
done


echo && echo "Press [Enter] to detach orphaned volumes..." && read

echo && echo ">> Detaching orphaned volumes:"

for VOLUME in "${ORPHANED_VOLUMES[@]}"; do
    volume_id=$(echo "$VOLUME" | awk '{print $1}')
    echo ".. Detaching volume: $volume_id"
    if [[ $DRY_RUN == "--dry-run" ]]; then
        aws ec2 detach-volume --volume-id "$volume_id" --dry-run
    else
        aws ec2 detach-volume --volume-id "$volume_id" | jq
    fi
done


echo