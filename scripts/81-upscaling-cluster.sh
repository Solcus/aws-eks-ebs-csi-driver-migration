#!/usr/bin/env bash

original_replica_counts_file=$1

while read -r namespace owner replicas pvc_name pod; do

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "$(date +'%H:%M:%S') >> Dryrun: Scaling $owner in $namespace to $replicas replicas"
  else
    echo "Scaling $owner in $namespace to $replicas replicas"
    kubectl scale "$owner" -n "$namespace" --replicas="$replicas"
  fi
  
done < "$original_replica_counts_file"
