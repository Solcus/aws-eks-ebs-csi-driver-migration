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
#### DONT MANUALLY DELETE THE PVs COLLECTIVELY !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#### THESE ARE CLUSTER RESOURCES AND CANNOT BE TARGETED BY NAMESPACES !!!!!!!!!!!
