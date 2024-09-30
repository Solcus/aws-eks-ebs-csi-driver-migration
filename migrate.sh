#!/usr/bin/env bash

function stepbystep() {
    set +e
    [[ $STEP_BY_STEP == "true" ]] && echo && echo "$(date +'%H:%M:%S') Press [Enter] to $1..." && read
    set -e
}

# Parse command line arguments
source ./scripts/0-args.sh

# Preperations
stepbystep "validate the environment"
source ./scripts/1-validate.sh

stepbystep "set up the prerequisites"
source ./scripts/2-prereqs.sh

stepbystep "gather information from the cluster"
source ./scripts/3-gather.sh

# Downscale the cluster
if [[ $cluster_scale == "true" ]]; then
    stepbystep "start downscaling the cluster for sc '$old_storage_class_name' in namespaces: '$namespaces'"
    source ./scripts/80-downscaling-cluster.sh $old_storage_class_name "$(echo $namespaces | tr " " ",")"
fi

# Automatic migration
stepbystep "start migrating the PVCs"
if [[ -s $runtime_folder/temp-pvcs-with-default-sc.txt ]]; then
    while read -r pvc; do
        namespace=$(echo $pvc | awk '{print $1}')
        pvc_name=$(echo $pvc | awk '{print $2}')
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "$(date +'%H:%M:%S') >> Dryrun: Migrating PVC $pvc_name in namespace $namespace"
        else
            echo "> Migrating PVC $pvc_name in namespace $namespace"
            sleep 5
            source ./scripts/4-migrate_pvc.sh $namespace $pvc_name
        fi

    done <<< "$(cat $runtime_folder/temp-pvcs-with-default-sc.txt)"
else 
    echo "$(date +'%H:%M:%S') -- No PVCs found using StorageClass '$old_storage_class_name'"
fi

# Upscale the cluster
if [[ $cluster_scale == "true" ]]; then
    stepbystep "start upscaling the cluster"
    source ./scripts/81-upscaling-cluster.sh $downscaleOutputFile
fi

# Cleanup
stepbystep "clean up the runtime"
source ./scripts/5-cleanup.sh
