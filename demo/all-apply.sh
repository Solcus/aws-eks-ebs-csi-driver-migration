#!/bin/bash

for file in *_.yaml; do
    echo "Applying $file"
    kubectl apply -f "$file"
done

for file in *.yaml; do
    if [[ $file == *_.yaml ]]; then
        continue
    fi
    echo "Applying $file"
    kubectl apply -f "$file"
done