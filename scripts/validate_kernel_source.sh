#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <kernel-root> <defconfig-path>" >&2
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || { usage; exit 64; }

kernel_root="$(realpath "$1")"
defconfig_rel="$2"

[[ "$defconfig_rel" != /* ]] || fail "defconfig path must be relative"
[[ "$defconfig_rel" != *".."* ]] || fail "defconfig path must not contain '..'"

[[ -f "$kernel_root/Makefile" ]] || fail "kernel Makefile is missing"
[[ -f "$kernel_root/$defconfig_rel" ]] || fail "defconfig is missing: $defconfig_rel"

if [[ -d "$kernel_root/common/drivers" ]]; then
  drivers_dir="$kernel_root/common/drivers"
elif [[ -d "$kernel_root/drivers" ]]; then
  drivers_dir="$kernel_root/drivers"
else
  fail "drivers/ or common/drivers/ is missing"
fi

[[ -f "$drivers_dir/Makefile" ]] || fail "drivers Makefile is missing"
[[ -f "$drivers_dir/Kconfig" ]] || fail "drivers Kconfig is missing"

grep -Eq '^VERSION[[:space:]]*=[[:space:]]*4([[:space:]]|$)' "$kernel_root/Makefile" || \
  fail "this builder is restricted to Linux 4.9 sources"
grep -Eq '^PATCHLEVEL[[:space:]]*=[[:space:]]*9([[:space:]]|$)' "$kernel_root/Makefile" || \
  fail "this builder is restricted to Linux 4.9 sources"

# ReSukiSU manual-hook mode requires kernel-side call sites. These checks are
# intentionally performed before integration so a README-only or unpatched
# source tree fails with a useful message rather than after a long compile.
declare -A required_hooks=(
  ["fs/stat.c"]="ksu_handle_stat"
  ["fs/exec.c"]="ksu_handle_execve"
  ["fs/open.c"]="ksu_handle_faccessat"
  ["kernel/reboot.c"]="ksu_handle_sys_reboot"
)

for relative_path in "${!required_hooks[@]}"; do
  marker="${required_hooks[$relative_path]}"
  [[ -f "$kernel_root/$relative_path" ]] || fail "required source file is missing: $relative_path"
  grep -q "$marker" "$kernel_root/$relative_path" || \
    fail "manual ReSukiSU hook marker '$marker' is missing from $relative_path"
done

echo "[OK] Linux 4.9 source tree, defconfig and minimum manual-hook markers validated"
