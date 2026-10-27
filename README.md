# Vulkan Support for Unraid

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Unraid](https://img.shields.io/badge/Unraid-6.10%2B-orange)](https://unraid.net/)

Vulkan loader, `vulkaninfo` and the NVIDIA Vulkan ICD configuration for Unraid hosts with NVIDIA GPUs.
Needed for Vulkan workloads in Docker containers such as **RealityScan** (RSNode under Wine), **Blender** and other Vulkan applications.

## What it installs

- **Vulkan loader** `libvulkan.so.1` and **vulkaninfo**, built from the Khronos sources
  ([Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader), [Vulkan-Tools](https://github.com/KhronosGroup/Vulkan-Tools))
  at Vulkan SDK **1.4.363.0**. They are built on Ubuntu 20.04 (glibc 2.31), so they run on every Unraid release from 6.10 (glibc 2.33) on.
- **NVIDIA ICD manifest**: if the NVIDIA driver already ships `nvidia_icd.json` (in `/etc/vulkan/icd.d` or `/usr/share/vulkan/icd.d`), it is used as is.
  Only if none exists, the plugin writes `/etc/vulkan/icd.d/nvidia_icd.json` pointing at `libGLX_nvidia.so.0`.
  If `libGLX_nvidia.so.0` is missing, the install log warns that the NVIDIA Driver plugin is not installed.
- **Web page** under **Settings → Utilities → Vulkan Support**: driver, ICD source (driver or generated), loader version, `vulkaninfo --summary`, Docker settings.

The plugin does not set `VK_ICD_FILENAMES`/`VK_DRIVER_FILES` globally. The loader finds `/etc/vulkan/icd.d` on its own,
and a global override would hide every other Vulkan driver on the host (Unraid 7 ships Mesa ICDs).

## Requirements

- Unraid 6.10.0 or later
- NVIDIA GPU with Vulkan support
- [NVIDIA Driver plugin](https://forums.unraid.net/topic/98978-plugin-nvidia-driver/) (ich777), which also provides the NVIDIA container runtime

## Installation

**Community Applications:** Apps → search "Vulkan" → Install.

**Manually:** Plugins → Install Plugin:

```
https://raw.githubusercontent.com/Martynyuu/unraid-vulkan/main/vulkan.plg
```

Check on the host:

```bash
vulkaninfo --summary
```

## Docker containers

Use the NVIDIA runtime with the `graphics` driver capability (`all` includes it). Since NVIDIA Container Toolkit 1.12 the toolkit then
mounts the driver libraries (`libGLX_nvidia.so.0`, …), the DRM devices and the host's Vulkan ICD manifest into the container
(at `/etc/vulkan/icd.d/nvidia_icd.json`). That is why the host needs a manifest at all: without one there is nothing to inject.

| Setting | Value | Required |
|---|---|---|
| Extra Parameters | `--runtime=nvidia` | yes |
| Variable `NVIDIA_VISIBLE_DEVICES` | `all` or a GPU UUID from `nvidia-smi -L` | yes |
| Variable `NVIDIA_DRIVER_CAPABILITIES` | `all` (at least `graphics,compute,utility`) | yes |
| Path `/etc/vulkan/icd.d` → `/etc/vulkan/icd.d`, read-only | `-v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro` | fallback |
| Device `/dev/dri` | `--device /dev/dri` | optional |

- The ICD mount is a fallback for older toolkit versions that do not inject the manifest; with a current toolkit it is redundant but harmless.
  If the web page reports that the manifest comes from the driver in `/usr/share/vulkan/icd.d`, mount that file instead:
  `-v /usr/share/vulkan/icd.d/nvidia_icd.json:/etc/vulkan/icd.d/nvidia_icd.json:ro`.
- Mounting `/usr/share/vulkan/icd.d` is not needed.
- The container brings its own Vulkan loader (`libvulkan1` in Debian/Ubuntu images). The host loader from this plugin is only used on the host.
- To force the NVIDIA driver inside a container (e.g. to hide llvmpipe), set
  `VK_DRIVER_FILES=/etc/vulkan/icd.d/nvidia_icd.json` and, for loaders older than 1.3.207 (e.g. Ubuntu 20.04 images), also the deprecated `VK_ICD_FILENAMES` to the same path.
- On Unraid use `--runtime=nvidia` (as the NVIDIA Driver plugin documents) rather than `--gpus all`.

### Example: RealityScan RSNode (Wine)

```bash
docker run -d --name rsnode \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  --device /dev/dri \
  -v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
  -v /mnt/user/scans:/data \
  your-rsnode-image
```

Check inside the container:

```bash
docker exec rsnode vulkaninfo --summary     # NVIDIA GPU must be listed
```

Under Wine, `winevulkan` uses the container's 64-bit `libvulkan.so.1`, which in turn loads the NVIDIA ICD.

### Example: Blender

```bash
docker run -d --name blender \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
  -v /mnt/user/blender:/config \
  lscr.io/linuxserver/blender
```

## Troubleshooting

**"Cannot create Vulkan instance" / no GPU on the host**

1. `nvidia-smi` must show the GPU (NVIDIA Driver plugin installed, nouveau not loaded: `lsmod | grep nouveau`).
2. The web page shows where the ICD manifest comes from. `cat /var/local/emhttp/plugins/vulkan/icd.state` shows the same.
3. Plugins install alphabetically at boot, the NVIDIA driver before this plugin. If the driver was installed later, reinstall this plugin or reboot.

**No GPU inside the container**

1. Is `--runtime=nvidia` set and `NVIDIA_DRIVER_CAPABILITIES` `all` (or does it contain `graphics`)? `compute,utility` alone gives CUDA but no Vulkan.
2. `docker exec <container> ls /etc/vulkan/icd.d` must list `nvidia_icd.json`.
3. `docker exec <container> sh -c 'ldconfig -p | grep libGLX_nvidia'` must find the library.
4. The image needs a Vulkan loader (`apt install libvulkan1`).

## Building

`build.sh` clones Vulkan-Headers, Vulkan-Loader and Vulkan-Tools at the tag in the `vulkansdk` entity of `vulkan.plg`, builds them and
packages `packages/vulkan-<version>-x86_64-1.txz`. Needs git, a C/C++ compiler, make, xz and binutils; CMake ≥ 3.22.1 is downloaded if missing.

Build on a system with glibc ≤ 2.33, otherwise the package will not run on Unraid 6.10/6.11. The script checks this and fails if the
binaries need newer glibc symbols (`GLIBC_MAX`, default 2.33):

```bash
docker run --rm -v "$PWD":/src -w /src ubuntu:20.04 bash -c \
  'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
     build-essential git ca-certificates curl xz-utils binutils file && ./build.sh'
```

The build also runs the packaged `vulkaninfo` against the Khronos mock driver as a smoke test.

## Releasing

Actions → **Build & Release** → Run workflow on `main` → version, e.g. `2026.10.27`. The workflow builds the package in `ubuntu:20.04`,
writes version and MD5 into `vulkan.plg`, commits that to `main`, tags the commit `v2026.10.27` and publishes the release.
Add the `<CHANGES>` entry to `vulkan.plg` and `CHANGELOG.md` before running it. Tags are always `v` + version; package file names and the
PLG version have no `v`.

## License

MIT, see [LICENSE](LICENSE). The Vulkan loader and tools are Apache-2.0 (licenses in `/usr/doc/vulkan-<version>/`).

## Credits

- [Khronos Group / LunarG](https://vulkan.lunarg.com/) for the Vulkan loader and tools
- [ich777](https://github.com/ich777) for the NVIDIA Driver plugin and plugin examples
- Unraid plugin community

## Support

- [GitHub Issues](https://github.com/Martynyuu/unraid-vulkan/issues)
- [Unraid Forums](https://forums.unraid.net/)
- If this project was helpful consider buying me a [hot chocolate](https://ko-fi.com/strudel9)
