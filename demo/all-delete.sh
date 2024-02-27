#!/bin/bash

for file in *.yaml; do
    if [[ $file == *_.yaml ]]; then
        continue
    fi
    echo "Deleting $file"
    kubectl delete -f "$file"
done

for file in *_.yaml; do
    echo "Deleting $file"
    kubectl delete -f "$file"
done


#### DONT MAKE THE SAME MISTAKE AGAIN !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!





















































# # Delete PVCs
# kubectl delete pvc --all -n demo-csi-migration

# # Delete PVs
# kubectl delete pv --all -n demo-csi-migration

# # Delete VolumeSnapshots
# kubectl delete volumesnapshot --all -n demo-csi-migration

# # Delete VolumeSnapshotContents
# kubectl delete volumesnapshotcontent --all -n demo-csi-migration

# # Patch resources to remove finalizers
# kubectl patch pvc --all -n demo-csi-migration -p '{"metadata":{"finalizers":[]}}' --type=merge
# kubectl patch pv --all -n demo-csi-migration -p '{"metadata":{"finalizers":[]}}' --type=merge
# kubectl patch volumesnapshot --all -n demo-csi-migration -p '{"metadata":{"finalizers":[]}}' --type=merge
# kubectl patch volumesnapshotcontent --all -n demo-csi-migration -p '{"metadata":{"finalizers":[]}}' --type=merge
