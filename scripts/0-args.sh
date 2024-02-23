#!/usr/bin/env bash

# :: TAKES command line arguments 
# :: SETS global variables

# Default values
new_storage_class_name=""
new_snapshot_class_name=""
snapshot_prefix=""
namespaces=""

runtime_folder="$(dirname $0)/.runtime"
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
        *)    # unknown option
            shift # past argument
            ;;
    esac
done


# SET variables
DRY_RUN=${dry_run:-"false"}

## CSI Drivers
OLD_CSI_DRIVER="kubernetes.io/aws-ebs"  # in-tree driver - deprecated in K8S v1.27
NEW_CSI_DRIVER="ebs.csi.aws.com"        # AWS EBS CSI driver

## Storage Classes
OLD_STORAGE_CLASS=$(kubectl get sc | grep "$OLD_CSI_DRIVER" | awk '{print $1}')
NEW_STORAGE_CLASS=$(kubectl get sc | grep "$NEW_CSI_DRIVER" | awk '{print $1}')

create_new_storage_class="false"

[[ -z "$OLD_STORAGE_CLASS" ]] && echo "No storage class found for $OLD_CSI_DRIVER" 1>&2 && exit 1

if [[ -z "$NEW_STORAGE_CLASS" && -z "$new_storage_class_name" ]]; then
    echo "No storage class found for $NEW_CSI_DRIVER" 1>&2
    echo "Please provide a storage class name for $NEW_CSI_DRIVER using --storage-class to create one." 1>&2
    exit 1
elif [[ $new_storage_class_name && $NEW_STORAGE_CLASS != "$new_storage_class_name" ]]; then
    NEW_STORAGE_CLASS="$new_storage_class_name"
    create_new_storage_class="true"
fi

## Volume Snapshot Classes
NEW_SNAPSHOT_CLASS=$(kubectl get volumesnapshotclass | grep "$NEW_CSI_DRIVER" | awk '{print $1}')

create_new_snapshot_class="false"

if [[ -z "$NEW_SNAPSHOT_CLASS" && -z "$new_snapshot_class_name" ]]; then
    echo "No volume snapshot class found for $NEW_CSI_DRIVER" 1>&2
    echo "Please provide a volume snapshot class name for $NEW_CSI_DRIVER using --snapshot-class to create one." 1>&2
    exit 1
elif [[ $new_snapshot_class_name && $NEW_SNAPSHOT_CLASS != "$new_snapshot_class_name" ]]; then
    NEW_SNAPSHOT_CLASS="$new_snapshot_class_name"
    create_new_snapshot_class="true"
fi

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
CREATE_NEW_SC      : $create_new_storage_class
CREATE_NEW_VSC     : $create_new_snapshot_class
PARAMETERS         : $parameters
SNAPSHOT_PREFIX    : $snapshot_prefix
NAMESPACES         : $namespaces
EOF
