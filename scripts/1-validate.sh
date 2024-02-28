#!/usr/bin/env bash

# Check if CSI Driver is installed
if [[ -z $(kubectl get csidrivers | grep $NEW_CSI_DRIVER) ]]; then
    echo ">> CSI Driver '$NEW_CSI_DRIVER' is not installed"
    echo "!! Please install the CSI Driver '$NEW_CSI_DRIVER' before running this script" 1>&2
    exit 1
else
    echo ">> CSI Driver '$NEW_CSI_DRIVER' is installed"
fi

# Check if Snapshot CRDs are installed
if [[ -z $(kubectl get crd | grep volumesnapshots.snapshot.storage.k8s.io) ]]; then
    echo ">> VolumeSnapshot CRDs are not installed"
    echo "!! Please install the VolumeSnapshot CRDs before running this script" 1>&2
    exit 1
else
    echo ">> VolumeSnapshot CRDs are installed"
fi

# Check if the old StorageClass exists
if [[ -z $(kubectl get sc | grep $OLD_STORAGE_CLASS) ]]; then
    echo ">> StorageClass '$OLD_STORAGE_CLASS' does not exist"
    echo "!! Please make sure you select the right old storage class" 1>&2
    exit 1
else
    echo ">> Old StorageClass '$OLD_STORAGE_CLASS' exists"
fi

# Check if the new StorageClass exists
if [[ -z $(kubectl get sc | grep $NEW_STORAGE_CLASS) ]]; then
    echo ">> StorageClass '$NEW_STORAGE_CLASS' does not exist"
    echo "!! Please create the StorageClass '$NEW_STORAGE_CLASS' before running this script" 1>&2
    exit 1
else
    echo ">> New StorageClass '$NEW_STORAGE_CLASS' exists"
fi

# Check if the snapshot class exists
if [[ -z $(kubectl get volumesnapshotclass | grep $NEW_SNAPSHOT_CLASS) ]]; then
    echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' does not exist"
    echo "!! Please create the VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' before running this script" 1>&2
    exit 1
else
    echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' exists"
fi

# Check if the snapshot csi driver is the same as the new csi driver
if [[ -z $(kubectl get volumesnapshotclass $NEW_SNAPSHOT_CLASS -o jsonpath='{.driver}') ]]; then
    echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' does not have a driver"
    echo "!! Please make sure the VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' has a driver" 1>&2
    exit 1
else
    SNAPSHOT_CSI_DRIVER=$(kubectl get volumesnapshotclass $NEW_SNAPSHOT_CLASS -o jsonpath='{.driver}')
    if [[ "$SNAPSHOT_CSI_DRIVER" != "$NEW_CSI_DRIVER" ]]; then
        echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' has a different driver"
        echo "!! Please make sure the VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' has the same driver as the new CSI driver" 1>&2
        exit 1
    else
        echo ">> VolumeSnapshotClass '$NEW_SNAPSHOT_CLASS' has the same driver as the new CSI driver"
    fi
fi

# Check if old driver is either kubernetes.io/aws-ebs or ebs.csi.aws.com
if [[ "$OLD_CSI_DRIVER" != "kubernetes.io/aws-ebs" ]] && [[ "$OLD_CSI_DRIVER" != "ebs.csi.aws.com" ]]; then
    echo ">> Old CSI Driver '$OLD_CSI_DRIVER' is not supported"
    echo "!! Please make sure you select the right old EBS CSI driver" 1>&2
    exit 1
else
    echo ">> Old CSI Driver '$OLD_CSI_DRIVER' is supported"
fi

# Check if new driver is ebs.csi.aws.com
if [[ "$NEW_CSI_DRIVER" != "ebs.csi.aws.com" ]]; then
    echo ">> New CSI Driver '$NEW_CSI_DRIVER' is not supported"
    echo "!! Please make sure you select the right new EBS CSI driver" 1>&2
    exit 1
else
    echo ">> New CSI Driver '$NEW_CSI_DRIVER' is supported"
fi

# Check if the namespace exists
for namespace in $namespaces; do
    if [[ -z $(kubectl get ns | grep $namespace) ]]; then
        echo ">> Namespace '$namespace' does not exist"
        echo "!! Please make sure you select the right namespace" 1>&2
        exit 1
    else
        echo ">> Namespace '$namespace' exists"
    fi
done

[[ $STEP_BY_STEP == "true" ]] && echo && echo "Press [Enter] to prepare the SC..." && read