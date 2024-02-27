#!/usr/bin/env bash

source ./scripts/0-args.sh
source ./scripts/1-validate.sh
source ./scripts/2-prereqs.sh
source ./scripts/3-gather.sh

# Automatic migration
echo ">> Automatic migration"
while read -r pvc; do
    namespace=$(echo $pvc | awk '{print $1}')
    pvc_name=$(echo $pvc | awk '{print $2}')

    echo "> Migrating PVC $pvc_name in namespace $namespace"

    source ./scripts/4-migrate_pvc.sh $namespace $pvc_name

done <<< "$(cat $runtime_folder/temp-pvcs-with-default-sc.txt)"

source ./scripts/5-cleanup.sh
