#!/bin/bash
set -uo pipefail

# rpi-image-gen config parsing test suite
# Usage: just run it

IGTOP=$(readlink -f "$(dirname "$0")/../../")
SRC="${IGTOP}/test/configurations"
IG=${IGTOP}/rpi-image-gen

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

print_header "DRY RUN CONFIG TESTS"

run_test "dryconfig1 - docker" \
    "printf 'n\n' | $IG build -S ${SRC} -c trixie-rpios-min-docker.yaml -I" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig2 - splash" \
    "printf 'n\n' | $IG build -S ${SRC} -c trixie-ab-min-splash.yaml -I" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig3 - examples/slim" \
    "printf 'n\n' | $IG build -S ${IGTOP}/examples/slim -c pi5-slim.yaml -I" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig4 - examples/webkiosk" \
    "printf 'n\n' | $IG build -S ${IGTOP}/examples/webkiosk -c kiosk.yaml -I" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig5 - examples/ota" \
    "printf 'n\n' | $IG build -S ${IGTOP}/examples/ota -c ota.yaml -I -- IGconf_connect_authkey=rpuak_foobar" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig5 - cm4" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpi-cm4" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig5 - cm4 lite w/emmc" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpi-cm4 IGconf_device_variant=lite IGconf_device_storage_type=emmc" \
    1 \
    "Configuration should reject cm4 lite w/emmc"

run_test "dryconfig6 - cm5" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpi-cm5" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig7 - cm5 lite w/emmc" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpi-cm5 IGconf_device_variant=lite IGconf_device_storage_type=emmc" \
    1 \
    "Configuration should reject cm5 lite w/emmc"

run_test "dryconfig8 - pi5" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpi5" \
    0 \
    "Configuration should parse correctly"

run_test "dryconfig9 - pi5 w/emmc" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpi5 IGconf_device_storage_type=emmc" \
    1 \
    "Configuration should reject pi5 w/emmc"

run_test "dryconfig10 - zero2w" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_device_layer=rpizero2w" \
    0 \
    "Configuration should parse correctly"

run_test "dryconfig11 - partuuid w/clear pmap" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_image_devid_scheme=partuuid IGconf_image_pmap=clear" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig12 - partuuid w/crypt pmap" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_image_devid_scheme=partuuid IGconf_image_pmap=crypt" \
    1 \
    "Configuration should reject partuuid with an encrypted root"

run_test "dryconfig13 - by-slot w/crypt pmap" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_image_devid_scheme=by-slot IGconf_image_pmap=crypt" \
    0 \
    "Configuration should parse successfully"

run_test "dryconfig14 - zero disksig" \
    'out=$(printf "n\n" | $IG build -c trixie-minbase.yaml -I -- IGconf_image_disksig=0x00000000 2>&1); \
     test $? -ne 0 && echo "$out" | grep -q "does not match pattern"' \
    0 \
    "Configuration should reject an all-zero disk signature"

run_test "dryconfig15 - explicit disksig" \
    "printf 'n\n' | $IG build -c trixie-minbase.yaml -I -- IGconf_image_disksig=0x0000000a" \
    0 \
    "Configuration should accept a non-zero disk signature"

# Every demo value in $1 must reach runner hooks as configured
check_hook_values() {
    local cfg=$1 bdir name want
    bdir=$(printf 'n\n' | $IG build -c "$cfg" -I 2>&1 |
           sed -n 's/^IGconf_sys_bootstrapdir *: *//p' | head -n1)
    test -n "$bdir" || return 1
    while IFS= read -r -d '' name && IFS= read -r -d '' want; do
        [ "$( . "${IGTOP}/lib/common.sh" && runenv "$bdir/final.env" printenv "IGconf_demo_${name}")" = "$want" ] ||
            { echo "$name"; return 1; }
    done < <(python3 -c 'import sys,yaml
for k,v in yaml.safe_load(open(sys.argv[1]))["demo"].items():
    sys.stdout.write(f"{k}\0{v}\0")' "$cfg")
}

run_test "dryconfig16 - quoted values" \
    "check_hook_values ${SRC}/config/quoted-values.yaml" \
    0 \
    "Values containing quotes should reach runner hooks as configured"

run_test "dryconfig17 - multiline string value" \
    'out=$(printf "n\n" | $IG build -c '"${SRC}"'/config/multiline-hostname.yaml -I 2>&1); \
     test $? -ne 0 && echo "$out" | grep -q "must be a single line"' \
    0 \
    "A string variable should reject a value spanning lines"

run_test "dryconfig17b - NUL in value" \
    'out=$(printf "n\n" | $IG build -c '"${SRC}"'/config/nul-value.yaml -I 2>&1); \
     test $? -ne 0 && echo "$out" | grep -q "IGconf_device_hostname: contains a NUL byte"' \
    0 \
    "A value containing a NUL should be rejected"

# What a layer hook run by bin/runner sees for $2 when the layer's .d/env holds
# $1 (printf format, so the file need not end in a newline)
runner_env_hook() {
    local d rc
    d=$(mktemp -d)
    mkdir -p "$d/probe.d/hooks"
    printf "$1" > "$d/probe.d/env"
    printf '#!/bin/bash\nprintf "%%s" "$%s" > "%s/out"\n' "$2" "$d" > "$d/probe.d/hooks/prebuild10-probe"
    chmod +x "$d/probe.d/hooks/prebuild10-probe"
    : > "$d/probe.yaml"
    printf 'probe:1.0.0:%s/probe.yaml:%s/probe.yaml:x:%s/work\n' "$d" "$d" "$d" > "$d/plan"
    IGTOP="$IGTOP" "$IGTOP/bin/runner" prebuild "$d/plan" >/dev/null 2>&1 && cat "$d/out"
    rc=$?
    rm -rf "$d"
    return $rc
}

run_test "envfile - line-based layer env" \
    "test \"\$(runner_env_hook 'A=\"bar baz\"\\n# c\\nB=last' A)\" = 'bar baz' && \
     test \"\$(runner_env_hook 'A=\"bar baz\"\\n# c\\nB=last' B)\" = last" \
    0 \
    "A line-based layer env file, without a final newline, should reach hooks"

run_test "dryconfig18 - multiline string substitution" \
    'out=$(printf "n\n" | $IG build -c '"${SRC}"'/config/multiline-subst-hostname.yaml -I 2>&1); \
     test $? -ne 0 && echo "$out" | grep -q "IGconf_device_hostname spans multiple lines after expansion"' \
    0 \
    "A string variable should reject command substitution spanning lines"

run_test "dryconfig19 - multiline undeclared override" \
    'out=$(printf "n\n" | $IG build -c trixie-minbase.yaml -I -- "IGconf_demo_x=$(printf "a\nb")" 2>&1); \
     test $? -ne 0 && echo "$out" | grep -q "IGconf_demo_x spans multiple lines after expansion"' \
    0 \
    "A variable no layer declares as string-multiline should not span lines"

# Dry run $1 with overrides $2.., then check what a runner hook sees for
# IGconf_ssh_pubkey_user1 is the two keys in two-keys.pub
check_hook_keys() {
    local cfg=$1 out bdir; shift
    out=$(printf 'n\n' | $IG build -c "$cfg" -I -- "$@" 2>&1)
    bdir=$(echo "$out" | sed -n 's/^IGconf_sys_bootstrapdir *: *//p' | head -n1)
    test -n "$bdir" || return 1
    # As runner hooks receive it
    [ "$( . "${IGTOP}/lib/common.sh" && runenv "$bdir/final.env" printenv IGconf_ssh_pubkey_user1)" = \
      "$(cat "${SRC}/config/two-keys.pub")" ] &&
    # As handed to bdebstrap, shown under FINAL ENV
    printf '%s\n' "$out" | grep -A1 -xF 'IGconf_ssh_pubkey_user1 : ssh-ed25519 AAAAONE me@laptop' |
        grep -qxF 'ssh-ed25519 AAAATWO me@desktop'
}

run_test "dryconfig20 - multiline value" \
    "check_hook_keys ${SRC}/config/multiline-pubkey.yaml" \
    0 \
    "A string-multiline variable should reach runner hooks with every line"

run_test "dryconfig21 - multiline substitution" \
    "check_hook_keys ${SRC}/config/multiline-subst-pubkey.yaml" \
    0 \
    "Command substitution spanning lines should reach a string-multiline variable"

run_test "dryconfig22 - multiline override" \
    "check_hook_keys trixie-minbase.yaml \"IGconf_ssh_pubkey_user1=\$(cat ${SRC}/config/two-keys.pub)\"" \
    0 \
    "A command line override spanning lines should reach a string-multiline variable"

# final.env stays one record per line, a multi-line value holding a NUL for
# each line break, so ordinary entries read as before
check_final_env_lines() {
    local bdir
    bdir=$(printf 'n\n' | $IG build -c "$1" -I 2>&1 |
           sed -n 's/^IGconf_sys_bootstrapdir *: *//p' | head -n1)
    test -n "$bdir" || return 1
    [ "$(grep -ac '' "$bdir/final.env")" = "$(grep -acE '^[A-Za-z_][A-Za-z0-9_]*=' "$bdir/final.env")" ] &&
    [ "$(grep -a '^IGconf_ssh_pubkey_user1=' "$bdir/final.env" | tr -dc '\0' | wc -c)" = 1 ] &&
    grep -aqx 'IGconf_image_suffix="img"' "$bdir/final.env"
}

run_test "dryconfig23 - final.env records" \
    "check_final_env_lines ${SRC}/config/multiline-pubkey.yaml" \
    0 \
    "final.env should keep one record per line with a multi-line value"

print_summary
exit 0

