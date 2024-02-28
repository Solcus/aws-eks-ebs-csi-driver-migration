#!/bin/bash

# Set the node ID
INSTANCE_ID=$1

# Get the instance ID of the EC2 node
# INSTANCE_ID=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].InstanceId" --filters "Name=tag:Name,Values=$NODE_ID" --output text)

echo "Instance ID: $INSTANCE_ID"

# List all EBS volumes attached to the node
ATTACHED_VOLUMES=$(aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" --query "Volumes[*].VolumeId" --output text)

# Make a list of the attached volumes text
ATTACHED_VOLUMES=$(echo "$ATTACHED_VOLUMES" | tr '  ' ' ')

echo "Attached Volumes: $ATTACHED_VOLUMES"
echo "Amount: $(echo "$ATTACHED_VOLUMES" | wc -l)"

# Get all PersistentVolumes in the Kubernetes cluster
K8S_PVS=$(kubectl get pv --no-headers -o custom-columns=":spec.awsElasticBlockStore.volumeID" | awk -F'/' '{print $NF}')
# Add volumeHandles to that
K8S_PVS+=$(kubectl get pv --no-headers -o custom-columns=":spec.csi.volumeHandle" | awk -F'/' '{print $NF}')

# Initialize an empty array to hold orphaned volumes
ORPHANED_VOLUMES=()

# Check each attached volume against Kubernetes PVs
for VOLUME in $ATTACHED_VOLUMES; do
    if ! echo "$K8S_PVS" | grep -qw "$VOLUME"; then
        ORPHANED_VOLUMES+=("$VOLUME")
    fi
done

# Output the list of orphaned volumes
echo "Orphaned Volumes:"
echo "Amount: ${#ORPHANED_VOLUMES[@]}"

# Order the orphaned volumes list alphabetically
IFS=$'\n' ORPHANED_VOLUMES=($(sort <<<"${ORPHANED_VOLUMES[*]}"))
unset IFS

for VOLUME in "${ORPHANED_VOLUMES[@]}"; do
    volume_name=$(aws ec2 describe-volumes --volume-ids "$VOLUME" --query "Volumes[*].Tags[?Key=='Name'].Value" --output text)
    
    pvc_name="pvc-$(echo "$volume_name" | grep 'pvc-' | head -n 1 | awk -F'pvc-' '{print $2}')"

    # echo "$VOLUME - $volume_name - $pvc_name"
    
    if [[ "$pvc_name" != "pvc-" ]]; then
        pv_exists=$(kubectl get pv | grep "$pvc_name")
        if [[ -z "$pv_exists" ]]; then
            echo "PVC '$pvc_name' - Volume $VOLUME - does not exists in the cluster"
        else
            echo "PVC '$pvc_name' - Volume $VOLUME - exists in the cluster"
        fi
    fi

done



# # Loop over the list of orphaned volumes and detach them
# for VOLUME in "${ORPHANED_VOLUMES[@]}"; do
#     echo "Detaching volume: $VOLUME from $INSTANCE_ID"
#     aws ec2 detach-volume --volume-id "$VOLUME"
#     # Optional: Wait for the volume to be detached
#     # aws ec2 wait volume-available --volume-ids "$VOLUME"
# done


15.8 -ecb
