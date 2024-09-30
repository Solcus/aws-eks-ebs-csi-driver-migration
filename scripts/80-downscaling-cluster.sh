#!/usr/bin/env bash

# Set the StorageClass name
storageClass=$1
namespaces=$2

# File to store the original replica counts

# backup_folder="$(dirname $0)/.backup/$(date +%s)"
# runtime_folder="$(dirname $0)/.runtime"
# rm -drf $runtime_folder
# mkdir -p $runtime_folder
# mkdir -p $backup_folder

if [[ -z "$runtime_folder" ]]; then
  echo "runtime_folder is not set. Exiting..."
  exit 1
fi

if [[ -z "$backup_folder" ]]; then
  echo "backup_folder is not set. Exiting..."
  exit 1
fi

downscaleOutputFile="$runtime_folder/original_replica_counts.txt"
> "$downscaleOutputFile"

# Find all PVCs that use the StorageClass
if [ -z "$storageClass" ]; then
  echo "Usage: $0 <storageClass>"
  exit 1
fi

## Namespaces
if [[ -z "$namespaces" ]]; then
    namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
else 
    namespaces=$(echo $namespaces | tr "," " ")
fi

for namespace in $namespaces; do
  pvc_names=($(kubectl get pvc -n $namespace -o=jsonpath='{.items[?(@.spec.storageClassName=="'$storageClass'")].metadata.name}'))    
  
  if [[ ${#pvc_names[@]} -eq 0 ]]; then
    echo "$(date +'%H:%M:%S') -- No PVCs found in namespace $namespace using StorageClass '$storageClass'"
    continue
  else
    echo "$(date +'%H:%M:%S') ++ Found the PVCs using StorageClass '$storageClass' in namespace $namespace:"
    echo "$(date +'%H:%M:%S') >> ${pvc_names[@]}"
  fi

  # Loop through each PVC and find the Deployments and StatefulSets using them
  for pvc_name in "${pvc_names[@]}"
  do
    pod=$(kubectl get pod -n ${namespace} -o jsonpath='{.items[?(@.spec.volumes[*].persistentVolumeClaim.claimName=="'$pvc_name'")].metadata.name}')
    
    if [[ -z "$pod" ]]; then
      echo "$(date +'%H:%M:%S') -- No Pods found in namespace $namespace using PVC '$pvc_name'"
      continue
    else
      echo "$(date +'%H:%M:%S') ++ Found the Pods using PVC '$pvc_name' in namespace $namespace:"
      echo "$(date +'%H:%M:%S') >> $pod"
    fi

    owner=$(kubectl get pod -n ${namespace} $pod -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')  

    if [[ $(echo $owner | cut -d'/' -f1) == "ReplicaSet" ]]; then
      owner=$(kubectl get -n $namespace $owner -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')
    fi

    replicas=$(kubectl get $owner -n $namespace -o jsonpath='{.spec.replicas}')

    infoset="$namespace $owner $replicas $pvc_name $pod"
    echo "$(date +'%H:%M:%S') >> $infoset"

    # If the combination of namespace and owner is not in the file, add it
    if ! grep -q "$namespace $owner" "$downscaleOutputFile"; then
      echo "$infoset" >> "$downscaleOutputFile"
    fi

  done

done

echo
cat $downscaleOutputFile
echo

# Scale down all Deployments and StatefulSets to 0 replicas
while read -r namespace owner replicas pvc_name pod; do

    # If dryrun is enabled, skip scaling down
    if [[ $DRY_RUN == "true" ]]; then
      echo "$(date +'%H:%M:%S') >> Dryrun: Skipping scaling down '$owner' in namespace '$namespace' to 0 replicas. Original replica count was '$replicas'."
      continue
    fi

    echo "$(date +'%H:%M:%S') >> Scaling down '$owner' in namespace '$namespace' to 0 replicas. Original replica count was '$replicas'."
    
    kubectl scale "$owner" -n "$namespace" --replicas=0
    
    # Wait until pod is gone
    while [[ $(kubectl get pod -n $namespace $pod 2>/dev/null) ]]; do
      echo "$(date +'%H:%M:%S') .. Waiting for pod '$pod' in namespace '$namespace' to be terminated..."
      sleep 5
    done

done < "$downscaleOutputFile"


# Finish
echo "$(date +'%H:%M:%S') All relevant Deployments and StatefulSets have been scaled down. Check '$downscaleOutputFile' for original replica counts:"
cat $downscaleOutputFile
echo
