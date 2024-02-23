#!/usr/bin/env bash

# RESTORE StorageClass defaults
if [[ "$migr_volumeBindingMode" != $(kubectl get sc $NEW_STORAGE_CLASS -o jsonpath='{.volumeBindingMode}') ]]; then
    echo ">> Finalizing StorageClass $NEW_STORAGE_CLASS"
    echo ">> Restoring volumeBindingMode to $migr_volumeBindingMode"
    if [[ $DRY_RUN == "false" ]]; then
        kubectl patch storageclass $NEW_STORAGE_CLASS -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        kubectl patch storageclass $NEW_STORAGE_CLASS -p '{"volumeBindingMode": "'$migr_volumeBindingMode'"}'
    fi
fi

# REMOVE temporary files
rm -drf $runtime_folder
