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

mkdir -p \
  "$kernel/drivers" \
  "$kernel/arch/arm64/configs" \
  "$kernel/fs" \
  "$kernel/kernel" \
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
EOF

cat > "$kernel/fs/stat.c" <<'EOF'
extern int ksu_handle_stat(void);
EOF
cat > "$kernel/fs/exec.c" <<'EOF'
extern int ksu_handle_execveat(void);
EOF
cat > "$kernel/fs/open.c" <<'EOF'
extern int ksu_handle_faccessat(void);
EOF
cat > "$kernel/kernel/reboot.c" <<'EOF'
extern int ksu_handle_sys_reboot(void);
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

# A second run must be idempotent.
bash "$repo_root/scripts/integrate_resukisu.sh" "$kernel" "$resukisu" "$defconfig_rel"
[[ "$(grep -Fc "$expected_make_line" "$kernel/drivers/Makefile")" -eq 1 ]]
[[ "$(grep -Fc "$expected_kconfig_line" "$kernel/drivers/Kconfig")" -eq 1 ]]
[[ "$(grep -Fc 'CONFIG_KSU=y' "$kernel/$defconfig_rel")" -eq 1 ]]
[[ "$(grep -Fc 'CONFIG_KSU_MANUAL_HOOK=y' "$kernel/$defconfig_rel")" -eq 1 ]]

# Wrong kernel version must fail before integration.
cp "$kernel/Makefile" "$kernel/Makefile.good"
sed -i 's/PATCHLEVEL = 9/PATCHLEVEL = 14/' "$kernel/Makefile"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected Linux 4.14 fixture to be rejected" >&2
  exit 1
fi
mv "$kernel/Makefile.good" "$kernel/Makefile"

# Missing manual hook must fail with a clear validation error.
mv "$kernel/fs/open.c" "$kernel/fs/open.c.saved"
if bash "$repo_root/scripts/validate_kernel_source.sh" "$kernel" "$defconfig_rel"; then
  echo "expected missing faccessat hook fixture to be rejected" >&2
  exit 1
fi
mv "$kernel/fs/open.c.saved" "$kernel/fs/open.c"

echo "All integration tests passed"
