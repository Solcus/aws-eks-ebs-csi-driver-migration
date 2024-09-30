#!/usr/bin/env bash

# # RESTORE StorageClass defaults
# stepbystep "update the SC..."

# if [[ "$migr_volumeBindingMode" != $(kubectl get sc $NEW_STORAGE_CLASS -o jsonpath='{.volumeBindingMode}') ]]; then
#     echo "$(date +'%H:%M:%S') >> Finalizing StorageClass $NEW_STORAGE_CLASS"
#     echo "$(date +'%H:%M:%S') >> Restoring volumeBindingMode to $migr_volumeBindingMode"
#     if [[ $DRY_RUN == "false" ]]; then
#         echo "$(date +'%H:%M:%S') > Waiting for 10 seconds before restoring volumeBindingMode..."
#         sleep 10
#         # kubectl patch storageclass $NEW_STORAGE_CLASS -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
#         kubectl get sc $NEW_STORAGE_CLASS -o json | jq --arg migr_volumeBindingMode ${migr_volumeBindingMode} '.volumeBindingMode = $migr_volumeBindingMode' > $runtime_folder/${NEW_STORAGE_CLASS}_after.json
#         kubectl replace -f $runtime_folder/${NEW_STORAGE_CLASS}_after.json --force
#     fi
# fi


# REMOVE temporary files
stepbystep "delete the runtime folder..."

cp -r $runtime_folder $backup_folder
rm -drf $runtime_folder