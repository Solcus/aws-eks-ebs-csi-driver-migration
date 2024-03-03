

CLUSTER_NAME=$1

folder_of_this_file=$(dirname $(realpath $0))
INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${CLUSTER_NAME}" --query "Reservations[].Instances[].InstanceId" --output text)

for instance in $INSTANCE_IDS; do
  echo "Press [Enter] to detach orphaned volumes from instance $instance..." && read
  source $folder_of_this_file/91-detach_orphaned_volumes.sh $instance
done
