#!/usr/bin/env bash

# # CHECK and SET volumeBindingMode
# given_parameters=$(echo $parameters | sed 's/,/ /g')

# for parameter in $given_parameters; do
#     key=$(echo $parameter | cut -d'=' -f1)
#     value=$(echo $parameter | cut -d'=' -f2)

#     case $key in
#         "volumeBindingMode")
#             migr_volumeBindingMode=$value
#             ;;
#         *)
#             echo "$(date +'%H:%M:%S') Unknown parameter: $key"
#             exit 1
#             ;;
#     esac
# done

# if [[ -z "$migr_volumeBindingMode" ]]; then
#     migr_volumeBindingMode=$(kubectl get sc $NEW_STORAGE_CLASS -o jsonpath='{.volumeBindingMode}')
# fi

# # SET volumeBindingMode to Immediate
# if [[ "$migr_volumeBindingMode" != "Immediate" ]]; then
#     echo "$(date +'%H:%M:%S') >> Setting StorageClass volumeBindingMode from '$migr_volumeBindingMode' to 'Immediate'"
#     if [[ $DRY_RUN == "false" ]]; then
#         kubectl get sc $NEW_STORAGE_CLASS -o json | jq '.volumeBindingMode = "Immediate"' > $runtime_folder/${NEW_STORAGE_CLASS}_before.json
#         kubectl replace -f $runtime_folder/${NEW_STORAGE_CLASS}_before.json --force
#     fi
# fi

echo
