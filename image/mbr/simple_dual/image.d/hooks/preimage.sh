#!/bin/bash

set -eu

fs=$1
genimg_in=$2


# Load pre-defined UUIDs
source "${IGconf_image_outputdir}/img_uuids"


[ -n "${BOOT_VOLID:-}" ] || die "preimage: stale img_uuids, re-run the filesystem stage"

MKE2FS_ARGS_STR="-U $ROOT_UUID ${IGconf_fs_ext4_mkfs_args:-}"
BTRFS_ARGS_STR="-U $ROOT_UUID ${IGconf_fs_btrfs_mkfs_args:-}"
VFAT_ARGS_STR="-S $IGconf_device_sector_size -i $BOOT_VOLID ${IGconf_fs_vfat_mkfs_args:-}"


# Write genimage template
cat "$LAYER_DIR/genimage.cfg.in.$IGconf_image_rootfs_type" | sed \
   -e "s|<IMAGE_DIR>|$IGconf_image_outputdir|g" \
   -e "s|<IMAGE_NAME>|$IGconf_image_name|g" \
   -e "s|<IMAGE_SUFFIX>|$IGconf_image_suffix|g" \
   -e "s|<FW_SIZE>|$IGconf_image_boot_part_size|g" \
   -e "s|<ROOT_SIZE>|$IGconf_image_root_part_size|g" \
   -e "s|<SETUP>|'$(readlink -ef "$LAYER_DIR/setup.sh")'|g" \
   -e "s|<MKE2FS_CONF>|'$(readlink -ef "$LAYER_DIR/mke2fs.conf")'|g" \
   -e "s|<MKE2FS_EXTRAARGS>|$MKE2FS_ARGS_STR|g" \
   -e "s|<BTRFS_EXTRAARGS>|$BTRFS_ARGS_STR|g" \
   -e "s|<VFAT_EXTRAARGS>|$VFAT_ARGS_STR|g" \
   -e "s|<BOOT_LABEL>|$IGconf_image_boot_label|g" \
   -e "s|<ROOT_LABEL>|$IGconf_image_root_label|g" \
   -e "s|<BOOT_UUID>|$BOOT_UUID|g" \
   -e "s|<ROOT_UUID>|$ROOT_UUID|g" \
   -e "s|<DISK_SIGNATURE>|$IGconf_image_disksig|g" \
   > ${genimg_in}/genimage.cfg


if grep -q '<[A-Z][A-Z0-9_]*>' ${genimg_in}/genimage.cfg; then
   die "preimage: unsubstituted placeholder in genimage.cfg"
fi

# The by-slot links depend on the rule matching the labels genimage is about to
# write. An --image-only rebuild does not re-run the customize hook that renders
# it, so check the rule in the filesystem rather than trusting it was rendered
# for these labels.
rules=${fs}/etc/udev/rules.d/99-rpi-05-image.rules
[ -f "${rules}" ] || die "preimage: ${rules} not found"
grep -q "^SUBSYSTEM.*ID_FS_LABEL}==\"${IGconf_image_boot_label}\".*SYMLINK+=\"disk/by-slot/boot\"" "${rules}" ||
   die "preimage: udev rule does not bind boot_label '${IGconf_image_boot_label}' to by-slot/boot"
grep -q "^SUBSYSTEM.*ID_FS_LABEL}==\"${IGconf_image_root_label}\".*SYMLINK+=\"disk/by-slot/system\"" "${rules}" ||
   die "preimage: udev rule does not bind root_label '${IGconf_image_root_label}' to by-slot/system"
