# ReSukiSU 4.9 AnyKernel3 Builder

用于验证、集成并编译 **Linux 4.9 + ReSukiSU Manual Hook** 内核，然后使用设备专用 AnyKernel3 模板打包。

## 当前状态

旧工作流不能生成可刷入内核，原因包括：

- `TJ-Releases/crDroidPlusPlus_kernel` 的 `main` 分支只有 README，不是完整内核源树；
- 工作流复制的 `ReSukiSU/kernel/drivers/resukisu` 路径不存在；
- 仅复制驱动目录不会自动接入内核的 Kconfig 和 Makefile；
- Linux 4.9 使用 ReSukiSU Manual Hook 时，还必须事先修改对应内核调用点；
- 直接使用未配置的官方 AnyKernel3 模板可能写入错误设备或分区；
- 内核、ReSukiSU 和 AnyKernel3 都跟随浮动分支，无法复现构建结果。

因此，新工作流不再在每次推送时盲目编译，也不会自动选择其他内核仓库。

## 仓库内容

```text
.github/workflows/build.yml       # 验证与手动构建流水线
scripts/validate_kernel_source.sh # Linux 4.9 源树和 Manual Hook 检查
scripts/integrate_resukisu.sh     # 确定性 Kconfig/Makefile 集成
tests/test_integration.sh         # 集成脚本和失败路径测试
```

## 自动验证

每次 Pull Request 或推送到 `main` 时，只执行安全、快速的静态验证：

- ShellCheck；
- Linux 4.9 源树夹具测试；
- 声明或注释不能冒充实际 Hook 调用；
- 缺失任一固定版本要求的 Hook 时必须失败；
- 出现旧式不兼容 Hook 时必须失败；
- 错误内核版本或错误 defconfig 路径必须失败；
- ReSukiSU 重复集成必须保持幂等；
- Kconfig、Makefile、符号链接和 defconfig 修改必须正确。

该阶段不会下载大型内核，也不会生成刷机包。

## 手动构建

在 GitHub Actions 中选择 **Validate and Build ReSukiSU 4.9 AK3**，点击 **Run workflow**，填写以下参数：

| 参数 | 要求 |
|---|---|
| `kernel_repository` | 完整 Linux 4.9 源码仓库，格式为 `owner/repository` |
| `kernel_commit` | 内核源码的完整 40 位 commit SHA |
| `defconfig_path` | `arch/arm64/configs/` 下以 `_defconfig` 结尾的路径 |
| `kernel_image_path` | 相对于 `O=out` 的最终镜像路径 |
| `resukisu_commit` | ReSukiSU 的完整 40 位 commit SHA |
| `anykernel_repository` | 已针对目标设备配置的 AnyKernel3 仓库 |
| `anykernel_commit` | AnyKernel3 模板的完整 40 位 commit SHA |
| `ak3_image_name` | AnyKernel3 模板期望的镜像文件名 |

工作流只获取指定 commit，不接受分支名或标签。构建产物包含：

- `ReSukiSU-4.9-AK3.zip`；
- `ReSukiSU-4.9-AK3.zip.sha256`；
- ZIP 内的 `build-manifest.txt`，记录三个源码 commit 和内核镜像 SHA-256。

## 固定 ReSukiSU 基线

默认基线为：

```text
058cdc931016cb2cb769ed063cce6d65d6df61e0
```

验证器按该 commit 的 `kernel/tools/manual_hook_check.mk` 对齐。更换 `resukisu_commit` 前，必须同步审查并更新验证规则，不能只替换 SHA。

## Linux 4.9 Manual Hook 前置条件

内核源码必须包含以下**实际函数调用**，仅有声明、注释或文档字符串不算通过：

| 文件 | 必需调用 |
|---|---|
| `fs/exec.c` | `ksu_handle_execveat(...)` |
| `fs/open.c` | `ksu_handle_faccessat(...)` |
| `fs/stat.c` | `ksu_handle_stat(...)` |
| `fs/stat.c` | `ksu_handle_newfstat_ret(...)` |
| `fs/stat.c` | `ksu_handle_fstat64_ret(...)` |
| `kernel/reboot.c` | `ksu_handle_sys_reboot(...)` |

固定基线还明确拒绝以下旧式或不兼容标记：

| 文件 | 禁止标记 |
|---|---|
| `fs/read_write.c` | `ksu_vfs_read_hook` |
| `security/selinux/hooks.c` | `is_ksu_transition` |
| `security/security.c` | `ksu_handle_rename` |

集成脚本随后执行：

- 创建 `drivers/kernelsu` 指向固定 ReSukiSU 源码的符号链接；
- 向驱动 Makefile 添加 `obj-$(CONFIG_KSU) += kernelsu/`；
- 向驱动 Kconfig 添加 `source "drivers/kernelsu/Kconfig"`；
- 启用 `CONFIG_KSU=y`；
- 启用 `CONFIG_KSU_MANUAL_HOOK=y`；
- 强制启用以下 Linux 4.9 可用的自动 Hook：
  - `CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y`；
  - `CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y`；
  - `CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y`。

如果实际内核还需要设备补丁、工具链参数或其他 Hook，必须先在内核源码仓库中完成并单独审查。

## AnyKernel3 要求

不要直接填写未配置的 `osm0sis/AnyKernel3` 通用模板。提供的仓库必须已经根据目标设备确认：

- `device.name*`；
- 启动分区与 A/B 槽位设置；
- 镜像文件名；
- DTB、DTBO 和 vendor_boot 处理方式；
- 刷写前后的设备检查与清理逻辑。

工作流会拒绝没有任何 `device.name` 配置的模板，但这不能代替实体设备审查。

## 安全说明

PR 验证成功只表示脚本、固定规则和测试夹具通过。手动内核构建成功也只表示指定源码能够编译和打包，均不代表 ZIP 可直接刷入。

刷入前仍应：

1. 核对目标设备、ROM、内核版本和启动分区；
2. 保存原始 boot/vendor_boot 镜像；
3. 检查 ZIP 内 `anykernel.sh` 和 `build-manifest.txt`；
4. 先在可恢复环境中测试；
5. 不要将未经实机验证的产物标记为稳定版。
