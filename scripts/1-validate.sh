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