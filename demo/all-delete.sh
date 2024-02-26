#!/bin/bash

for file in *.yaml; do
    echo "Deleting $file"
    kubectl delete -f "$file"
done
