#!/bin/bash

# Check all cluster in your kubeconfig for storage classes with the deprecated EBS CSI driver.

# Test if kubectx is installed
if ! command -v kubectx &> /dev/null
then
    echo "kubectx could not be found"
    echo "Please install kubectx to use this script"
    exit 1
fi

# Test if kubectl is installed
if ! command -v kubectl &> /dev/null
then
    echo "kubectl could not be found"
    echo "Please install kubectl to use this script"
    exit 1
fi

all_contexts=$(kubectx)

for context in $all_contexts; do
    echo && echo " .. Checking context: $context"
    kubectx $context > /dev/null
    old_scs=$(kubectl get sc | grep "kubernetes.io/aws-ebs" | awk '{print $1}')
    for sc in $old_scs; do
        echo " >> $sc"
        kubectl get pvc -A | grep " $sc " | awk '{print "  - " $1 "/" $2}'
    done
done