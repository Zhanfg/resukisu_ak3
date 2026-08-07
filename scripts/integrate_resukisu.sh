#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <kernel-root> <resukisu-root> <defconfig-path>" >&2
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

[[ $# -eq 3 ]] || { usage; exit 64; }

kernel_root="$(realpath "$1")"
resukisu_root="$(realpath "$2")"
defconfig_rel="$3"

[[ "$defconfig_rel" != /* ]] || fail "defconfig path must be relative"
[[ "$defconfig_rel" != *".."* ]] || fail "defconfig path must not contain '..'"

if [[ -d "$kernel_root/common/drivers" ]]; then
  drivers_dir="$kernel_root/common/drivers"
elif [[ -d "$kernel_root/drivers" ]]; then
  drivers_dir="$kernel_root/drivers"
else
  fail "drivers/ or common/drivers/ is missing"
fi

drivers_makefile="$drivers_dir/Makefile"
drivers_kconfig="$drivers_dir/Kconfig"
defconfig="$kernel_root/$defconfig_rel"
resukisu_kernel="$resukisu_root/kernel"

[[ -f "$drivers_makefile" ]] || fail "drivers Makefile is missing"
[[ -f "$drivers_kconfig" ]] || fail "drivers Kconfig is missing"
[[ -f "$defconfig" ]] || fail "defconfig is missing: $defconfig_rel"
[[ -f "$resukisu_kernel/Kconfig" ]] || fail "ReSukiSU kernel/Kconfig is missing"
[[ -f "$resukisu_kernel/Makefile" || -f "$resukisu_kernel/Kbuild" ]] || \
  fail "ReSukiSU kernel Makefile/Kbuild is missing"

link_path="$drivers_dir/kernelsu"
if [[ -e "$link_path" && ! -L "$link_path" ]]; then
  fail "$link_path exists and is not a symlink; refusing to overwrite it"
fi
rm -f "$link_path"
ln -s "$(realpath --relative-to="$drivers_dir" "$resukisu_kernel")" "$link_path"

make_line='obj-$(CONFIG_KSU) += kernelsu/'
if ! grep -Fqx "$make_line" "$drivers_makefile"; then
  printf '\n%s\n' "$make_line" >> "$drivers_makefile"
fi

kconfig_line='source "drivers/kernelsu/Kconfig"'
if ! grep -Fqx "$kconfig_line" "$drivers_kconfig"; then
  tmp_file="$(mktemp)"
  awk -v line="$kconfig_line" '
    BEGIN { inserted = 0 }
    !inserted && $0 == "endmenu" { print line; inserted = 1 }
    { print }
    END { if (!inserted) print line }
  ' "$drivers_kconfig" > "$tmp_file"
  cat "$tmp_file" > "$drivers_kconfig"
  rm -f "$tmp_file"
fi

set_config_y() {
  local symbol="$1"
  if grep -q "^CONFIG_${symbol}=" "$defconfig"; then
    sed -i "s/^CONFIG_${symbol}=.*/CONFIG_${symbol}=y/" "$defconfig"
  elif grep -q "^# CONFIG_${symbol} is not set$" "$defconfig"; then
    sed -i "s/^# CONFIG_${symbol} is not set$/CONFIG_${symbol}=y/" "$defconfig"
  else
    printf 'CONFIG_%s=y\n' "$symbol" >> "$defconfig"
  fi
}

set_config_y KSU
set_config_y KSU_MANUAL_HOOK

echo "[OK] ReSukiSU integrated through drivers/kernelsu"
echo "[OK] CONFIG_KSU=y and CONFIG_KSU_MANUAL_HOOK=y enabled in $defconfig_rel"
