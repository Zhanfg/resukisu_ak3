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
[[ "$defconfig_rel" == arch/arm64/configs/*_defconfig ]] || \
  fail "defconfig must be under arch/arm64/configs/ and end with _defconfig"

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

# ReSukiSU manual-hook mode requires kernel-side call sites. Declarations,
# comments and preprocessor lines are deliberately ignored to avoid treating
# a documented but unimplemented hook as a valid integration.
has_hook_call() {
  local source_file="$1"
  local marker="$2"

  awk -v marker="$marker" '
    /^[[:space:]]*(extern([[:space:]]|$)|\/\/|\/\*|\*|#)/ { next }
    $0 ~ marker "[[:space:]]*\\(" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$source_file"
}

declare -A required_hooks=(
  ["fs/stat.c"]="ksu_handle_stat"
  ["fs/exec.c"]="ksu_handle_execve"
  ["fs/open.c"]="ksu_handle_faccessat"
  ["kernel/reboot.c"]="ksu_handle_sys_reboot"
)

for relative_path in "${!required_hooks[@]}"; do
  marker="${required_hooks[$relative_path]}"
  source_file="$kernel_root/$relative_path"
  [[ -f "$source_file" ]] || fail "required source file is missing: $relative_path"
  has_hook_call "$source_file" "$marker" || \
    fail "manual ReSukiSU hook call '$marker(...)' is missing from $relative_path"
done

echo "[OK] Linux 4.9 source tree, arm64 defconfig and minimum manual-hook calls validated"
