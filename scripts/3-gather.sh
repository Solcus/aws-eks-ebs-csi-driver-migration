#!/usr/bin/env bash

echo ">> Listing PVCs using SC '$OLD_STORAGE_CLASS' in namespaces: $namespaces"

touch $runtime_folder/temp-pvcs-with-default-sc.txt $runtime_folder/temp-pvcs-with-custom-sc.txt

for namespace in $namespaces; do
    pvcs=$(kubectl get pvc -n $namespace | grep " $OLD_STORAGE_CLASS ")
    
    if [[ -z "$pvcs" ]]; then
        continue
    fi

    while read -r line; do
        pvc_name=$(echo $line | awk '{print $1}')
        if [[ -z "$pvc_name" ]]; then
            continue
        fi

        # Describe PVC to check who uses it
        pvc_user=$(kubectl describe pvc $pvc_name -n $namespace | grep "Used By:" | awk '{print $3}')
        
        # Describe pvc user to check Controlled By
        pvc_controller=$(kubectl describe pod $pvc_user -n $namespace | grep "Controlled By:" | awk '{print $3}')

        # Check if there is a StorageClass set in the PVC, then store it in a list of manual pvcs, else automatic pvcs
        pvc_sc=$(kubectl describe $pvc_controller -n $namespace | grep "StorageClass: " | awk '{print $2}')

        if [[ -z "$pvc_sc" ]]; then
            echo "$namespace $pvc_name" >> $runtime_folder/temp-pvcs-with-default-sc.txt
        else
            echo "$namespace $pvc_name" >> $runtime_folder/temp-pvcs-with-custom-sc.txt
        fi

    done <<< "$pvcs"
done

echo ">> PVCs using default SC: (automatic migration)"
if [[ -s $runtime_folder/temp-pvcs-with-default-sc.txt ]]; then
    cat $runtime_folder/temp-pvcs-with-default-sc.txt
else
    echo "None"
fi
echo

echo ">> PVCs using custom SC: (needs manual migration for maintainers side)"
if [[ -s $runtime_folder/temp-pvcs-with-custom-sc.txt ]]; then
    cat $runtime_folder/temp-pvcs-with-custom-sc.txt
else
    echo "None"
fi
echo 
