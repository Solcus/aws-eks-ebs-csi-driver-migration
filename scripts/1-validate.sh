#!/usr/bin/env bash

# Check if CSI Driver is installed
if [[ -z $(kubectl get csidrivers | grep $NEW_CSI_DRIVER) ]]; then
    echo ">> CSI Driver '$NEW_CSI_DRIVER' is not installed"
    echo "Please install the CSI Driver '$NEW_CSI_DRIVER' before running this script" 1>&2
    exit 1
else
    echo ">> CSI Driver '$NEW_CSI_DRIVER' is installed"
fi

# Check if Snapshot CRDs are installed
if [[ -z $(kubectl get crd | grep volumesnapshots.snapshot.storage.k8s.io) ]]; then
    echo ">> VolumeSnapshot CRDs are not installed"
    echo "Please install the VolumeSnapshot CRDs before running this script" 1>&2
    exit 1
else
    echo ">> VolumeSnapshot CRDs are installed"
fi

# Check if the old StorageClass exists
if [[ -z $(kubectl get sc | grep $OLD_STORAGE_CLASS) ]]; then
    echo ">> StorageClass '$OLD_STORAGE_CLASS' does not exist"
    echo "Please make sure you select the right old storage class" 1>&2
    exit 1
else
    echo ">> Old StorageClass '$OLD_STORAGE_CLASS' exists"
fi

# Check if the new StorageClass exists
if [[ -z $(kubectl get sc | grep $NEW_STORAGE_CLASS) ]]; then
    echo ">> StorageClass '$NEW_STORAGE_CLASS' does not exist"
    echo "Please create the StorageClass '$NEW_STORAGE_CLASS' before running this script" 1>&2
    exit 1
else
    echo ">> New StorageClass '$NEW_STORAGE_CLASS' exists"
fi

# Check if the snapshot class exists
if [[ -z $(kubectl get volumesnapshotclass | grep $NEW_SNAPSHOT_CLASS) ]]; then
    echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' does not exist"
    echo "Please create the VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' before running this script" 1>&2
    exit 1
else
    echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' exists"
fi

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to continue..." && read