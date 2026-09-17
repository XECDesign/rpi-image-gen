#!/bin/bash
set -uo pipefail

# rpi-image-gen image layer test suite
# Usage: just run it

IGTOP=$(readlink -f "$(dirname "$0")/../../")
LAYER="${IGTOP}/image/mbr/simple_dual"

# The hooks under test call die
. "${IGTOP}/lib/common.sh"

WORKDIR=$(mktemp -d -t image-layer.XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

declare -a FAILED_TEST_NAMES=()

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_test() {
    echo -e "${YELLOW}Testing: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((PASSED_TESTS++))
}

print_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    echo -e "${RED}  Error: $2${NC}"
    ((FAILED_TESTS++))
    FAILED_TEST_NAMES+=("$1")
}

run_test() {
    local test_name="$1"
    local command="$2"
    local expected_exit_code="$3"
    local description="$4"

    ((TOTAL_TESTS++))
    print_test "$test_name"

    local output
    output=$(eval "$command" 2>&1)
    local actual_exit_code=$?

    if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
        print_pass "$description"
    else
        print_fail "$description" "Expected exit code $expected_exit_code, got $actual_exit_code. Output: $output"
    fi

    echo ""
}

print_summary() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}TEST SUMMARY${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "Total tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"

    if [ ${#FAILED_TEST_NAMES[@]} -gt 0 ]; then
        echo -e "\n${RED}Failed tests:${NC}"
        for test in "${FAILED_TEST_NAMES[@]}"; do
            echo -e "${RED}  - $test${NC}"
        done
    fi

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed. Please check the output above.${NC}"
        exit 1
    fi
}

# Stage a root filesystem holding just the udev rule. Echoes the directory.
stage_rules() {
    local d
    d=$(mktemp -d -p "$WORKDIR")
    mkdir -p "$d/etc/udev/rules.d"
    cp "$LAYER/image.d/customize.overlay/etc/udev/rules.d/99-rpi-05-image.rules" \
       "$d/etc/udev/rules.d/"
    echo "$d"
}

# Environment preimage.sh reads. $1 output dir, $2 rootfs type, $3 boot label,
# $4 root label.
preimage_env() {
    echo "LAYER_DIR=$LAYER IGconf_image_outputdir=$1 IGconf_image_rootfs_type=$2" \
         "IGconf_image_name=t IGconf_image_suffix=img IGconf_image_boot_part_size=128M" \
         "IGconf_image_root_part_size=1G IGconf_device_sector_size=512" \
         "IGconf_image_disksig=0xAABBCCDD IGconf_image_boot_label=$3" \
         "IGconf_image_root_label=$4 IGconf_fs_ext4_mkfs_args=" \
         "IGconf_fs_btrfs_mkfs_args= IGconf_fs_vfat_mkfs_args="
}

# Stage an output directory holding img_uuids. Echoes the directory.
stage_uuids() {
    local d
    d=$(mktemp -d -p "$WORKDIR")
    cat > "$d/img_uuids" <<EOT
BOOT_VOLID=ABCD1234
BOOT_UUID=ABCD-1234
ROOT_UUID=00000000-0000-0000-0000-000000000002
CRYPT_UUID=00000000-0000-0000-0000-000000000003
EOT
    echo "$d"
}

RULE=etc/udev/rules.d/99-rpi-05-image.rules
HOOKS="$LAYER/image.d/hooks"

print_header "FILESYSTEM LABEL TESTS"

d=$(stage_rules)
run_test "fslabels-render-configured" \
    'IGconf_image_boot_label=bootfs IGconf_image_root_label=rootfs '"$HOOKS"'/customize20-fslabels '"$d"' && \
     grep -q '"'"'ID_FS_LABEL}=="bootfs", SYMLINK+="disk/by-slot/boot"'"'"' '"$d/$RULE"' && \
     grep -q '"'"'ID_FS_LABEL}=="rootfs", SYMLINK+="disk/by-slot/system"'"'"' '"$d/$RULE"' && \
     grep -q '"'"'ID_FS_LABEL}=="OSROOT_CRYPT"'"'"' '"$d/$RULE"' && \
     ! grep -q "<" '"$d/$RULE" \
    0 \
    "Hook should render configured labels and leave the LUKS rule alone"

d=$(stage_rules)
run_test "fslabels-render-defaults" \
    'IGconf_image_boot_label=BOOT IGconf_image_root_label=ROOT '"$HOOKS"'/customize20-fslabels '"$d"' && \
     grep -qx '"'"'SUBSYSTEM=="block", ENV{RPI_ONBOOTDEV}=="1", ENV{ID_FS_LABEL}=="BOOT", SYMLINK+="disk/by-slot/boot"'"'"' '"$d/$RULE"' && \
     grep -qx '"'"'SUBSYSTEM=="block", ENV{RPI_ONBOOTDEV}=="1", ENV{ID_FS_LABEL}=="ROOT", SYMLINK+="disk/by-slot/system"'"'"' '"$d/$RULE" \
    0 \
    "Default labels should reproduce the original rule"

# A rule that never matches leaves the device without by-slot symlinks
d=$(stage_rules)
sed -i '1a SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="<MKE2FS_CONF>", SYMLINK+="disk/by-slot/x"' "$d/$RULE"
run_test "fslabels-stray-placeholder" \
    'IGconf_image_boot_label=BOOT IGconf_image_root_label=ROOT '"$HOOKS"'/customize20-fslabels '"$d" \
    1 \
    "Hook should fail on an unsubstituted placeholder"

d=$(mktemp -d -p "$WORKDIR")
run_test "fslabels-missing-rule" \
    'IGconf_image_boot_label=BOOT IGconf_image_root_label=ROOT '"$HOOKS"'/customize20-fslabels '"$d" \
    1 \
    "Hook should fail when the udev rule is missing"

# preimage.sh checks the shipped rule against the configured labels, so give it
# a rootfs rendered for the same ones
rendered=$(stage_rules)
IGconf_image_boot_label=bootfs IGconf_image_root_label=rootfs \
    "$HOOKS/customize20-fslabels" "$rendered" >/dev/null 2>&1

for fstype in ext4 btrfs; do
    d=$(stage_uuids)
    g=$(mktemp -d -p "$WORKDIR")
    run_test "fslabels-genimage-$fstype" \
        "$(preimage_env "$d" "$fstype" bootfs rootfs)"' '"$HOOKS"'/preimage.sh '"$rendered"' '"$g"' && \
         grep -q '"'"'label = "bootfs"'"'"' '"$g"'/genimage.cfg && \
         grep -q '"'"'label = "rootfs"'"'"' '"$g"'/genimage.cfg && \
         grep -q -- "-i ABCD1234" '"$g"'/genimage.cfg' \
        0 \
        "Configured labels should reach genimage for $fstype"
done

# A customize hook that did not run leaves the shipped rule unrendered
d=$(stage_uuids)
g=$(mktemp -d -p "$WORKDIR")
fsdir=$(stage_rules)
run_test "fslabels-unrendered-rule" \
    "$(preimage_env "$d" ext4 bootfs rootfs)"' '"$HOOKS"'/preimage.sh '"$fsdir"' '"$g" \
    1 \
    "An unrendered udev rule in the rootfs should fail the build"

# Both labels present but bound to the wrong symlinks must not pass
d=$(stage_uuids)
g=$(mktemp -d -p "$WORKDIR")
swapped=$(stage_rules)
IGconf_image_boot_label=alpha IGconf_image_root_label=beta \
    "$HOOKS/customize20-fslabels" "$swapped" >/dev/null 2>&1
run_test "fslabels-swapped-labels" \
    "$(preimage_env "$d" ext4 beta alpha)"' '"$HOOKS"'/preimage.sh '"$swapped"' '"$g" \
    1 \
    "Labels bound to the wrong symlinks should fail the build"

# A commented-out rule is not a rule
d=$(stage_uuids)
g=$(mktemp -d -p "$WORKDIR")
disabled=$(stage_rules)
IGconf_image_boot_label=bootfs IGconf_image_root_label=rootfs \
    "$HOOKS/customize20-fslabels" "$disabled" >/dev/null 2>&1
sed -i 's|^SUBSYSTEM|# SUBSYSTEM|' "$disabled/$RULE"
run_test "fslabels-commented-rule" \
    "$(preimage_env "$d" ext4 bootfs rootfs)"' '"$HOOKS"'/preimage.sh '"$disabled"' '"$g" \
    1 \
    "A commented-out udev rule should fail the build"

print_summary
