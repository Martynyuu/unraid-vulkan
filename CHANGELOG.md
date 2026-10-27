# Changelog

All notable changes to this project are documented in this file.
Versions are release dates; git tags are `v` + version.

## [2026.10.27] - 2026-10-27

### Changed
- Vulkan loader and `vulkaninfo` updated from 1.3.204 (Ubuntu 22.04 packages) to Vulkan SDK 1.4.363.0,
  built from the Khronos sources in Ubuntu 20.04. The binaries need glibc 2.17 at most; the old package
  needed glibc 2.34 and libwayland-client/libX11/libxcb, so it could not run on Unraid 6.10 (glibc 2.33).
- `vulkaninfo` is built without X11/Wayland and with static libstdc++: no extra runtime libraries.
- Slackware package name `vulkan-<version>-x86_64-1.txz`; `upgradepkg`/`removepkg` work and old packages
  (`vulkan-v2026.03.02`) are removed on update.
- ICD handling: the NVIDIA driver's own `nvidia_icd.json` is used when present. A manifest is only generated
  in `/etc/vulkan/icd.d` when none exists, and its `api_version` is taken from the driver via `vulkaninfo`.
  No more `/usr/share/vulkan/icd.d` symlink.
- Install log warns when `libGLX_nvidia.so.0` is missing (NVIDIA Driver plugin not installed).
- Web page and helper script are shipped in the package. The page shows the ICD source (driver or generated),
  the loader version and `vulkaninfo --summary` (with a 10 s timeout).
- One Docker recommendation everywhere: `--runtime=nvidia`, `NVIDIA_VISIBLE_DEVICES`,
  `NVIDIA_DRIVER_CAPABILITIES=all`, optional read-only mount of `/etc/vulkan/icd.d`. Added a RealityScan RSNode example.
- Release workflow: builds in `ubuntu:20.04`, writes version and MD5 into `vulkan.plg`, commits it to `main`,
  tags `v<version>` and publishes the release (action-gh-release v3). Release links point to `Martynyuu/unraid-vulkan`.
- `icon.png` was an HTML error page; replaced by a real PNG.

### Removed
- Global `/etc/profile.d/vulkan.sh` (`VK_ICD_FILENAMES`, `NVIDIA_DRIVER_CAPABILITIES`). It hid every non-NVIDIA
  Vulkan driver on the host, and `NVIDIA_DRIVER_CAPABILITIES` has no effect outside containers. It is deleted on update.

## [2026.03.02b] - 2026-03-03

### Fixed
- Package download (Ubuntu 22.04 `vulkan-tools` 1.3.204 and `libvulkan1`)
- `vulkaninfo --summary` works in the terminal

## [2026.03.02a] - 2026-03-03

### Added
- `vulkaninfo` and Vulkan loader package

## [2026.03.02] - 2026-03-02

### Added
- Initial release: NVIDIA Vulkan ICD configuration, Docker mount instructions, Unraid web page
