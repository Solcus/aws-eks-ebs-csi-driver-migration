

# AWS EBS CSI Migration (EKS)

> [!TIP]
> This solution has been battletested in Production. 
> Check 'demo/scenarios' for the tested scenarios.

With the upgrade of the EKS cluster to version 1.27, the in-tree CSI Driver for AWS EBS Volumes will be deprecated. 
This module is used to migrate the EBS volumes to the new CSI driver for AWS EBS volumes.
It can also be used to migrate from any EBS storage class to another EBS storage class, for example when you want to change the type of EBS volume.
This is a common usecase when moving from GP2 to GP3 volumes.

<div style="color:grey">
    <sub>
        <b>Tags:</b>
        #AWS #EKS #EBS #CSIDriver #CSI #migration #Kubernetes #K8s #v1.27 #deprecation #in-tree #volumes #snapshots #storageclass #PVC #PV #GP2 #GP3 
    </sub>
</div>

---

## Context

The initial intent is to deal with the fact that the in-tree CSI Driver for AWS EBS Volumes in Kubernetes is deprecated and will be removed with With `version 1.27`.
This will cause trouble upon upgrading Kubernetes, because it would affect all existing resources that make use of the deprecated driver.

The old deprecated driver: `kubernetes.io/aws-ebs` 
The new correct driver: `ebs.csi.aws.com`

**Sources:**

- The in-tree driver is deprecated and will be **REMOVED** in Kubernetes 1.27. https://kubernetes.io/docs/concepts/storage/volumes/#awselasticblockstore
- After June 11th 2024, the standard **SUPPORT WILL END** for v1.26. https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html#kubernetes-release-calendar
- The old in-tree CSI driver interferes with the Snapshotcontroller. https://stackoverflow.com/a/75626313

Also, this tool can be used to migrate from any EBS storage class to another EBS storage class as well, for example when you want to change the type of EBS volume.
This is a common usecase when moving from GP2 to GP3 volumes [AWS DOCS](https://aws.amazon.com/blogs/containers/migrating-amazon-eks-clusters-from-gp2-to-gp3-ebs-volumes/).


## Verify

How to verify if a migration from the in-tree driver is relevant for your cluster:

1. Check the version of your cluster.
    ```bash
    kubectl version
    ```

2. Check if the `correct` AWS EBS CSIDriver is installed in your cluster as an EKS add-on.
*(Mind that you wont see the `kubernetes.io/aws-ebs` driver, because it is in-tree and not a CSI driver.)*
    ```bash
    kubectl get csidrivers | grep "ebs.csi.aws.com"
    ```

3. Check your storageclasses and see which provisioners they are using. 
    ```bash
    kubectl get storageclass | grep "kubernetes.io/aws-ebs" # This is using the deprecated driver

    kubectl get storageclass | grep "ebs.csi.aws.com" # This is using the correct driver

    kubectl get storageclass | grep " (default) " # This is the default storageclass, used when no storageclass is specified in a PVC
    ```
    
4. Check if any PVC's are using the deprecated driver.
    ```bash
    kubectl get pvc -A | grep " $(kubectl get storageclass | grep "kubernetes.io/aws-ebs" | awk '{print $1}') " 
    ```


If you have PVC's that are using a StorageClass that is using the deprecated driver, you should consider migrating them to the new driver.


## Migration Process

The migration process is done in a set of steps, which are described below. These steps are automated with the set of scripts in this repository. 
Using this automated tool, please look [here](#automated-migration).

### Cluster prerequisites

- Install new CSI-Drivers for EBS
- Install the Snapshot CRDs
- Install the SnapshotController
- Setup a new StorageClass with the new CSI-Driver
- Setup a new SnapshotClass with the new CSI-Driver

For the prerequisites, you can make use of the script `/prereqs/0-install-all.sh`, or the individual scripts, however, I would not recommend this.
I recommend deploying this on your cluster using infrastructure as code since these are permanent cluster resources.

### Migration

- Gather all PVCs in the selected namespaces
- Check if the PVCs are using the deprecated driver
- Check if the PVCs are using the default StorageClass
- Patch the StorageClass temporary to 'immediate' volumeBindingMode to prevent downtime
- Iterate over the PVCs/PVs:
    - Create a remote EBS snapshot in AWS (might take a while per volume)
    - Create VolumeSnapshotContent of the snapshot
    - Create VolumeSnapshot of the snapshotcontent
    - Delete old PVC
    - Create new PVC with the new StorageClass and the VolumeSnapshot as the source
    - Delete old PV
- Patch the StorageClass back and set it as default StorageClass

### Cleanup

- Delete the old StorageClass
- Delete the old CSIDriver
- Delete the old SnapshotClass

The cleanup is not automated, because it could easily interfere with automated IaC deployments.


## Automated Migration

The tool in this repository automates the migration process in the cluster, with minimal downtime and no efforts for the affected teams.
It validates the cluster and resources, and migrates every PVC that is using the current default StorageClass to the new StorageClass.

All non-default StorageClasses are not migrated, because this requires manual intervention from those who manage the deployments. They manually configured an alternative StorageClass, and therefore have to make configuration changes themselves.

To verify everything works as expected, try a dryrun first.

### Simple dryrun

This will automatically pick up the old and new StorageClas/SnapshotClass, and select all PVCs in all namespaces.
This option is suitable for most use-cases.

```bash
bash migrate.sh --dry-run
```

### Custom dryrun

You can optionally specify the target StorageClass, SnapshotClass, SnapshotPrefix, Parameters and Namespaces.

```bash
bash migrate.sh \
    --old-sc "storageclassname" \
    # MANDATORY: Specify the old storageclass
    --new-sc "storageclassname" \ 
    # MANDATORY: Specify the new storageclass
    --snapshot-class "snapshotclassname" \
    # MANDATORY: Specify the target snapshotclass
    --snapshot-prefix "migration-" \
    # OPTIONAL: Specify the prefix for the snapshots in AWS
    --parameters "key1=value1,key2=value2" \
    # OPTIONAL: Specify the parameters for the snapshotclass or storageclass
    --namespaces "default,namespace1" \
    # OPTIONAL: Specify the namespaces to migrate. If not specified, all namespaces are migrated. 
    --step-by-step \
    # OPTIONAL: Run the migration step by step. This will pause after every step to allow for manual verification.
    --cluster-scale \
    # OPTIONAL: Downscale the deployments and statefulsets in the cluster to 0 before migration and scale back up after migration.
    --pod-recreate \
    # OPTIONAL: Recreate the pods after the migration to ensure they are using the new PVC. If you wont, you have to manually restart the pods to reconnect to the volumes. ADVISED TO USE THIS.
    --dry-run
    # OPTIONAL: Run the migration in dryrun mode. This will not make any changes to the cluster.
```

### Execution

If everything looks as expected, you can run the same migration options without the `--dry-run` flag.



