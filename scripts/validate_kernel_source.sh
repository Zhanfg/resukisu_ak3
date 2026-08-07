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
  local call_pattern="$2"

  awk -v call_pattern="$call_pattern" '
    function strip_comments(line, output, start, finish, slash) {
      output = ""
      while (1) {
        if (in_block_comment) {
          finish = index(line, "*/")
          if (!finish) return output
          line = substr(line, finish + 2)
          in_block_comment = 0
        }

        start = index(line, "/*")
        slash = index(line, "//")
        if (slash && (!start || slash < start)) {
          return output substr(line, 1, slash - 1)
        }
        if (start) {
          output = output substr(line, 1, start - 1)
          line = substr(line, start + 2)
          in_block_comment = 1
          continue
        }
        return output line
      }
    }

    {
      code = strip_comments($0)
      if (code ~ /^[[:space:]]*(extern([[:space:]]|$)|#)/) next
      if (code ~ call_pattern "[[:space:]]*\\(") found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$source_file"
}

# This list mirrors the checks in ReSukiSU commit
# 058cdc931016cb2cb769ed063cce6d65d6df61e0 for Linux 4.9 when the three
# KSU_MANUAL_HOOK_AUTO_* options are enabled.
required_hook_specs=(
  "fs/exec.c|ksu_handle_execveat|ksu_handle_execveat"
  "fs/open.c|ksu_handle_faccessat|ksu_handle_faccessat"
  "fs/stat.c|ksu_handle_stat|ksu_handle_stat"
  "fs/stat.c|ksu_handle_newfstat_ret|ksu_handle_newfstat_ret"
  "fs/stat.c|ksu_handle_fstat64_ret|ksu_handle_fstat64_ret"
  "kernel/reboot.c|ksu_handle_sys_reboot|ksu_handle_sys_reboot"
)

for spec in "${required_hook_specs[@]}"; do
  IFS='|' read -r relative_path call_pattern hook_name <<< "$spec"
  source_file="$kernel_root/$relative_path"
  [[ -f "$source_file" ]] || fail "required source file is missing: $relative_path"
  has_hook_call "$source_file" "$call_pattern" || \
    fail "manual ReSukiSU hook call '$hook_name(...)' is missing from $relative_path"
done

# The pinned ReSukiSU build explicitly rejects these obsolete/incompatible
# hook markers, even when they only remain as dead code or comments.
incompatible_hook_specs=(
  "fs/read_write.c|ksu_vfs_read_hook"
  "security/selinux/hooks.c|is_ksu_transition"
  "security/security.c|ksu_handle_rename"
)

for spec in "${incompatible_hook_specs[@]}"; do
  IFS='|' read -r relative_path marker <<< "$spec"
  source_file="$kernel_root/$relative_path"
  [[ -f "$source_file" ]] || fail "required source file is missing: $relative_path"
  if grep -q "$marker" "$source_file"; then
    fail "incompatible ReSukiSU hook marker '$marker' is present in $relative_path"
  fi
done

echo "[OK] Linux 4.9 source tree matches pinned ReSukiSU manual-hook requirements"
