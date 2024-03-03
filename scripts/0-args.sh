#!/usr/bin/env bash

# :: TAKES command line arguments 
# :: SETS global variables

# Default values

set -e

new_storage_class_name=""
new_snapshot_class_name=""
snapshot_prefix=""
namespaces=""

runtime_folder="$(dirname $0)/.runtime"
rm -drf $runtime_folder
mkdir -p $runtime_folder

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --old-sc|-o)
            old_storage_class_name="$2"
            shift # past argument
            shift # past value
            ;;
        --new-sc|-s)
            new_storage_class_name="$2"
            shift # past argument
            shift # past value
            ;;
        --snapshot-class|-S)
            new_snapshot_class_name="$2"
            shift # past argument
            shift # past value
            ;;
        # --storage-class|-s)
        #     new_storage_class_name="$2"
        #     shift # past argument
        #     shift # past value
        #     ;;
        # --snapshot-class|-S)
        #     new_snapshot_class_name="$2"
        #     shift # past argument
        #     shift # past value
        #     ;;
        --snapshot-prefix|-P)
            snapshot_prefix="$2"
            shift # past argument
            shift # past value
            ;;
        --parameters|-p)
            parameters="$2"
            shift # past argument
            shift # past value
            ;;
        --namespaces|-n)
            namespaces="$2"
            shift # past argument
            shift # past value
            ;;
        --dry-run|-d)
            dry_run="true"
            shift # past argument
            ;;
        --step-by-step|-b)
            step_by_step="true"
            shift # past argument
            ;;
        *)    # unknown option
            shift # past argument
            ;;
    esac
done


# SET variables
DRY_RUN=${dry_run:-"false"}
STEP_BY_STEP=${step_by_step:-"false"}

# Set Storage class
[[ -z "$old_storage_class_name" ]] && echo "!! Please provide the old storage class name: --old-sc|-o" && exit 1
OLD_STORAGE_CLASS=$old_storage_class_name

# Set new storage class
[[ -z "$new_storage_class_name" ]] && echo "!! Please provide the new storage class name: --new-sc|-s" && exit 1
NEW_STORAGE_CLASS=$new_storage_class_name

# Set new snapshot class
[[ -z "$new_snapshot_class_name" ]] && echo "!! Please provide the snapshot class name: --snapshot-class|-S" && exit 1
NEW_SNAPSHOT_CLASS=$new_snapshot_class_name

# Get SC CSI Drivers
OLD_CSI_DRIVER=$(kubectl get sc $OLD_STORAGE_CLASS -o jsonpath='{.provisioner}')
NEW_CSI_DRIVER=$(kubectl get sc $NEW_STORAGE_CLASS -o jsonpath='{.provisioner}')

## Storage Classes
# OLD_STORAGE_CLASS=$(kubectl get sc -o jsonpath='{.items[?(@.provisioner=="'$OLD_CSI_DRIVER'")].metadata.name}')

# If new storage class var is set, use that, else lookup
# if [[ -z "$new_storage_class_name" ]]; then
#     NEW_STORAGE_CLASS=$(kubectl get sc | grep "$NEW_CSI_DRIVER" | awk '{print $1}' | head -n 1)
# else
#     NEW_STORAGE_CLASS="$new_storage_class_name"
# fi

## Volume Snapshot Classes
# if [[ -z "$new_snapshot_class_name" ]]; then
#     NEW_SNAPSHOT_CLASS=$(kubectl get volumesnapshotclass | grep "$NEW_CSI_DRIVER" | awk '{print $1}' | head -n 1)
# else
#     NEW_SNAPSHOT_CLASS="$new_snapshot_class_name"
# fi

# NEW_SNAPSHOT_CLASS=$(kubectl get volumesnapshotclass | grep "$NEW_CSI_DRIVER" | awk '{print $1}' | head -n 1)
vsc_api_version=$(kubectl get volumesnapshotclass $NEW_SNAPSHOT_CLASS -o jsonpath='{.apiVersion}')

## Remote snapshot prefix
[[ -z "$snapshot_prefix" ]] && snapshot_prefix="mtcv2-$(date +%s)-"

## Namespaces
if [[ -z "$namespaces" ]]; then
    namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
else 
    namespaces=$(echo $namespaces | tr "," " ")
fi

# PRINT global variables
cat << EOF
>> Global variables set:
DRY_RUN            : $DRY_RUN

OLD_STORAGE_CLASS  : $OLD_STORAGE_CLASS
OLD_CSI_DRIVER     : $OLD_CSI_DRIVER

NEW_STORAGE_CLASS  : $NEW_STORAGE_CLASS
NEW_CSI_DRIVER     : $NEW_CSI_DRIVER

NEW_SNAPSHOT_CLASS : $NEW_SNAPSHOT_CLASS
VSC_API_VERSION    : $vsc_api_version
SNAPSHOT_PREFIX    : $snapshot_prefix

PARAMETERS         : $parameters
NAMESPACES         : $namespaces
EOF

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to start validating..." && read
