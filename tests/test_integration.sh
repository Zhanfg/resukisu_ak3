#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

kernel="$tmp_root/kernel"
resukisu="$tmp_root/resukisu"
defconfig_rel="arch/arm64/configs/sdm845_defconfig"
expected_make_line="obj-\$(CONFIG_KSU) += kernelsu/"
expected_kconfig_line='source "drivers/kernelsu/Kconfig"'
auto_hook_symbols=(
  KSU_MANUAL_HOOK_AUTO_SETUID_HOOK
  KSU_MANUAL_HOOK_AUTO_INITRC_HOOK
  KSU_MANUAL_HOOK_AUTO_INPUT_HOOK
)

mkdir -p \
  "$kernel/drivers" \
  "$kernel/arch/arm64/configs" \
  "$kernel/fs" \
  "$kernel/kernel" \
  "$kernel/security/selinux" \
  "$resukisu/kernel"

cat > "$kernel/Makefile" <<'EOF'
VERSION = 4
PATCHLEVEL = 9
SUBLEVEL = 337
EOF

cat > "$kernel/drivers/Makefile" <<'EOF'
obj-y += base/
EOF

cat > "$kernel/drivers/Kconfig" <<'EOF'
menu "Device Drivers"
endmenu
EOF

cat > "$kernel/$defconfig_rel" <<'EOF'
CONFIG_ARM64=y
# CONFIG_KSU is not set
# CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK is not set
# CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK is not set
# CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK is not set
EOF

cat > "$kernel/fs/stat.c" <<'EOF'
extern int ksu_handle_stat(void);
extern int ksu_handle_newfstat_ret(void);
extern int ksu_handle_fstat64_ret(void);
void test_stat_hooks(void) {
  ksu_handle_stat();
  ksu_handle_newfstat_ret();
  ksu_handle_fstat64_ret();
}
EOF
cat > "$kernel/fs/exec.c" <<'EOF'
extern int ksu_handle_execveat(void);
void test_exec_hook(void) { ksu_handle_execveat(); }
EOF
cat > "$kernel/fs/open.c" <<'EOF'
extern int ksu_handle_faccessat(void);
void test_access_hook(void) { ksu_handle_faccessat(); }
EOF
cat > "$kernel/kernel/reboot.c" <<'EOF'
extern int ksu_handle_sys_reboot(void);
void test_reboot_hook(void) { ksu_handle_sys_reboot(); }
EOF
cat > "$kernel/fs/read_write.c" <<'EOF'
int read_write_fixture;
EOF
cat > "$kernel/security/selinux/hooks.c" <<'EOF'
int selinux_hook_fixture;
EOF
cat > "$kernel/security/security.c" <<'EOF'
int security_hook_fixture;
EOF

cat > "$resukisu/kernel/Kconfig" <<'EOF'
config KSU
  bool "ReSukiSU"
EOF
cat > "$resukisu/kernel/Makefile" <<'EOF'
obj-y += core/
EOF

bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"
bash "$repo_root/scripts/integrate_resukisu.sh" "$kernel" "$resukisu" "$defconfig_rel"

[[ -L "$kernel/drivers/kernelsu" ]]
[[ "$(realpath "$kernel/drivers/kernelsu")" == "$(realpath "$resukisu/kernel")" ]]
grep -Fqx "$expected_make_line" "$kernel/drivers/Makefile"
grep -Fqx "$expected_kconfig_line" "$kernel/drivers/Kconfig"
grep -Fqx 'CONFIG_KSU=y' "$kernel/$defconfig_rel"
grep -Fqx 'CONFIG_KSU_MANUAL_HOOK=y' "$kernel/$defconfig_rel"
for symbol in "${auto_hook_symbols[@]}"; do
  grep -Fqx "CONFIG_${symbol}=y" "$kernel/$defconfig_rel"
done

# A second run must be idempotent.
bash "$repo_root/scripts/integrate_resukisu.sh" "$kernel" "$resukisu" "$defconfig_rel"
[[ "$(grep -Fc "$expected_make_line" "$kernel/drivers/Makefile")" -eq 1 ]]
[[ "$(grep -Fc "$expected_kconfig_line" "$kernel/drivers/Kconfig")" -eq 1 ]]
[[ "$(grep -Fc 'CONFIG_KSU=y' "$kernel/$defconfig_rel")" -eq 1 ]]
[[ "$(grep -Fc 'CONFIG_KSU_MANUAL_HOOK=y' "$kernel/$defconfig_rel")" -eq 1 ]]
for symbol in "${auto_hook_symbols[@]}"; do
  [[ "$(grep -Fc "CONFIG_${symbol}=y" "$kernel/$defconfig_rel")" -eq 1 ]]
done

# Wrong kernel version must fail before integration.
cp "$kernel/Makefile" "$kernel/Makefile.good"
sed -i 's/PATCHLEVEL = 9/PATCHLEVEL = 14/' "$kernel/Makefile"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected Linux 4.14 fixture to be rejected" >&2
  exit 1
fi
mv "$kernel/Makefile.good" "$kernel/Makefile"

# Missing source file must fail with a clear validation error.
mv "$kernel/fs/open.c" "$kernel/fs/open.c.saved"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected missing faccessat hook source to be rejected" >&2
  exit 1
fi
mv "$kernel/fs/open.c.saved" "$kernel/fs/open.c"

# A declaration or comment without an actual call must not pass validation.
cp "$kernel/fs/open.c" "$kernel/fs/open.c.good"
cat > "$kernel/fs/open.c" <<'EOF'
extern int ksu_handle_faccessat(void);
/*
ksu_handle_faccessat(); documented but not integrated
*/
EOF
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected declaration-only faccessat marker to be rejected" >&2
  exit 1
fi
mv "$kernel/fs/open.c.good" "$kernel/fs/open.c"

# Every hook required by the pinned manual_hook_check.mk must be present.
cp "$kernel/fs/stat.c" "$kernel/fs/stat.c.good"
grep -v 'ksu_handle_fstat64_ret();' "$kernel/fs/stat.c.good" > "$kernel/fs/stat.c"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected missing fstat64 return hook call to be rejected" >&2
  exit 1
fi
mv "$kernel/fs/stat.c.good" "$kernel/fs/stat.c"

# Obsolete hooks rejected by the pinned ReSukiSU build must fail early.
printf '%s\n' 'int ksu_vfs_read_hook;' >> "$kernel/fs/read_write.c"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected incompatible ksu_vfs_read_hook marker to be rejected" >&2
  exit 1
fi
sed -i '/ksu_vfs_read_hook/d' "$kernel/fs/read_write.c"

# Defconfig paths outside arch/arm64/configs are not accepted.
cp "$kernel/$defconfig_rel" "$kernel/bad_defconfig"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "bad_defconfig"; then
  echo "expected non-arm64 defconfig path to be rejected" >&2
  exit 1
fi

echo "All integration tests passed"
