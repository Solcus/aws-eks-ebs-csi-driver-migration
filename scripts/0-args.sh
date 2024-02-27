#!/usr/bin/env bash

# :: TAKES command line arguments 
# :: SETS global variables

# Default values
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
        --storage-class|-s)
            new_storage_class_name="$2"
            shift # past argument
            shift # past value
            ;;
        --snapshot-class|-S)
            new_snapshot_class_name="$2"
            shift # past argument
            shift # past value
            ;;
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

## CSI Drivers
OLD_CSI_DRIVER="kubernetes.io/aws-ebs"  # in-tree driver - deprecated in K8S v1.27
NEW_CSI_DRIVER="ebs.csi.aws.com"        # AWS EBS CSI driver

## Storage Classes
OLD_STORAGE_CLASS=$(kubectl get sc | grep "$OLD_CSI_DRIVER" | awk '{print $1}' | head -n 1)

# If new storage class var is set, use that, else lookup
if [[ -z "$new_storage_class_name" ]]; then
    NEW_STORAGE_CLASS=$(kubectl get sc | grep "$NEW_CSI_DRIVER" | awk '{print $1}' | head -n 1)
else
    NEW_STORAGE_CLASS="$new_storage_class_name"
fi

## Volume Snapshot Classes
if [[ -z "$new_snapshot_class_name" ]]; then
    NEW_SNAPSHOT_CLASS=$(kubectl get volumesnapshotclass | grep "$NEW_CSI_DRIVER" | awk '{print $1}' | head -n 1)
else
    NEW_SNAPSHOT_CLASS="$new_snapshot_class_name"
fi

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
NEW_STORAGE_CLASS  : $NEW_STORAGE_CLASS
NEW_SNAPSHOT_CLASS : $NEW_SNAPSHOT_CLASS
VSC_API_VERSION    : $vsc_api_version
PARAMETERS         : $parameters
SNAPSHOT_PREFIX    : $snapshot_prefix
NAMESPACES         : $namespaces
EOF

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to continue..." && read
