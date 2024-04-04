#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

SSD_NVME_DEVICE_LIST=($(ls /sys/block | grep nvme | xargs -I. echo /dev/. || true))
SSD_NVME_DEVICE_COUNT=${#SSD_NVME_DEVICE_LIST[@]}
RAID_DEVICE=${RAID_DEVICE:-/dev/md0}
RAID_CHUNK_SIZE=${RAID_CHUNK_SIZE:-512}  # Kilo Bytes
FILESYSTEM_BLOCK_SIZE=${FILESYSTEM_BLOCK_SIZE:-4096}  # Bytes
STRIDE=$(expr $RAID_CHUNK_SIZE \* 1024 / $FILESYSTEM_BLOCK_SIZE || true)
STRIPE_WIDTH=$(expr $SSD_NVME_DEVICE_COUNT \* $STRIDE || true)


# Checking if provisioning already happend
if [[ "$(ls -A /media/disks)" ]]
then
  echo 'Volumes already present in "/media/disks"'
  echo -e "\n$(ls -Al /media/disks | tail -n +2)\n"
  echo "I assume that provisioning already happend, doing nothing!"
  sleep infinity
fi

# Perform provisioning based on nvme device count
case $SSD_NVME_DEVICE_COUNT in
"0")
  echo 'No devices found of type "Microsoft NVMe Direct Disk"'
  echo "Maybe your node selectors are not set correct"
  exit 1
  ;;
"1")
  mkfs.ext4 -m 0 -b $FILESYSTEM_BLOCK_SIZE $SSD_NVME_DEVICE_LIST
  DEVICE=$SSD_NVME_DEVICE_LIST
  ;;
*)
  mdadm --create --verbose $RAID_DEVICE --level=0 -c ${RAID_CHUNK_SIZE} \
    --raid-devices=${#SSD_NVME_DEVICE_LIST[@]} ${SSD_NVME_DEVICE_LIST[*]}
  while [ -n "$(mdadm --detail $RAID_DEVICE | grep -ioE 'State :.*resyncing')" ]; do
    echo "Raid is resyncing.."
    sleep 1
  done
  echo "Raid0 device $RAID_DEVICE has been created with disks ${SSD_NVME_DEVICE_LIST[*]}"
  mkfs.ext4 -m 0 -b $FILESYSTEM_BLOCK_SIZE -E stride=$STRIDE,stripe-width=$STRIPE_WIDTH $RAID_DEVICE
  DEVICE=$RAID_DEVICE
  ;;
esac

UUID=$(blkid -s UUID -o value $DEVICE)
mkdir -p /media/$UUID
mount -o defaults,noatime,discard,nobarrier --uuid $UUID /media/$UUID
echo "UUID=$UUID /media/$UUID ext4 defaults 0 2" | tee -a /etc/fstab
echo "Device $DEVICE has been mounted to /media/$UUID"

# https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner/blob/master/docs/operations.md#sharing-a-disk-filesystem-by-multiple-filesystem-pvs
for i in $(seq 1 100); do
  mkdir -p /media/${UUID}/vol${i} /media/disks/${UUID}_vol${i}
  mount --bind /media/${UUID}/vol${i} /media/disks/${UUID}_vol${i}
done

for i in $(seq 1 100); do
  echo "/media/${UUID}/vol${i} /media/disks/${UUID}_vol${i} none bind 0 0" | tee -a /etc/fstab
done

mkdir -p /media/${UUID}/indexer || exit 0
mkdir -p /media/${UUID}/search-head || exit 0
mkdir -p /media/indexer || exit 0
mkdir -p /media/search-head || exit 0
mkdir -p /media/disks

mount --bind /media/${UUID}/indexer /media/indexer
mount --bind /media/${UUID}/search-head /media/search-head

echo "/media/${UUID}/indexer /media/indexer none bind 0 0" | tee -a /etc/fstab
echo "/media/${UUID}/search-head /media/search-head none bind 0 0" | tee -a /etc/fstab

echo "NVMe SSD provisioning is done and I will go to sleep now"
#sleep infinity
