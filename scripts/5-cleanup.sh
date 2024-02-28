#!/usr/bin/env bash

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to detach the old volume from the node instance..." && read

# DETACH old volume from the node instance
if [[ $DRY_RUN == "false" ]]; then
    echo ">> Detaching old volume from the node instance..."
    aws ec2 detach-volume --volume-id $VOLUME_ID --force
else 
    echo ">> DRY_RUN: aws ec2 detach-volume --volume-id $VOLUME_ID --force"
fi

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to update the SC..." && read

# RESTORE StorageClass defaults
if [[ "$migr_volumeBindingMode" != $(kubectl get sc $NEW_STORAGE_CLASS -o jsonpath='{.volumeBindingMode}') ]]; then
    echo ">> Finalizing StorageClass $NEW_STORAGE_CLASS"
    echo ">> Restoring volumeBindingMode to $migr_volumeBindingMode"
    if [[ $DRY_RUN == "false" ]]; then
        echo "> Waiting for 10 seconds before restoring volumeBindingMode..."
        sleep 10
        # kubectl patch storageclass $NEW_STORAGE_CLASS -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        kubectl get sc $NEW_STORAGE_CLASS -o json | jq --arg migr_volumeBindingMode ${migr_volumeBindingMode} '.volumeBindingMode = $migr_volumeBindingMode' > $runtime_folder/${NEW_STORAGE_CLASS}_after.json
        kubectl replace -f $runtime_folder/${NEW_STORAGE_CLASS}_after.json --force
    fi
fi

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to delete the runtime folder..." && read

# REMOVE temporary files
rm -drf $runtime_folder