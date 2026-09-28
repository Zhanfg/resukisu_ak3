# resukisu_ak3

> Legacy / archive-ready builder. Active OnePlus 6 build and release orchestration has moved to [Zhanfg/abk-op6-kernel](https://github.com/Zhanfg/abk-op6-kernel).

This repository is retained for Git history and attribution. It is no longer an active build entrypoint.

## Canonical repositories

- Build/release orchestration: `Zhanfg/abk-op6-kernel`
- Kernel source: `ZhanfgBuild/kernel_oneplus_sdm845`

The build repository and kernel source remain separate.

## Preserved legacy work

- `review/reproducible-resukisu-build`: reproducible Linux 4.9 ReSukiSU/AnyKernel3 validation work. Its reusable validation and provenance ideas were adapted into the canonical OnePlus 6 builder.
- `linear-zh-lsposed`: unrelated historical work, intentionally not imported into the OnePlus 6 builder.

The Linux 4.9 source-mutation integration path was not copied into the Linux 4.19 OnePlus 6 builder.

## Consolidation evidence

- Canonical PR: https://github.com/Zhanfg/abk-op6-kernel/pull/9
- Standard Build Verified run: https://github.com/Zhanfg/abk-op6-kernel/actions/runs/36458937665
- PowerSave Build Verified run: https://github.com/Zhanfg/abk-op6-kernel/actions/runs/36458937425

Both runs verified the build pipeline and artifacts only. They do not constitute OnePlus 6 Boot Verified or Runtime Verified status.
