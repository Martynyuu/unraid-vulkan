# Vulkan Support for Unraid

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Unraid](https://img.shields.io/badge/Unraid-6.10%2B-orange)](https://unraid.net/)

Provides Vulkan loader, tools, and ICD configuration for Unraid systems with NVIDIA GPUs. Essential for running GPU-accelerated applications like **RealityScan**, **Blender**, and other Vulkan-dependent software in Docker containers.

## Features

- 🎮 **Vulkan Loader** - Core Vulkan runtime libraries
- 🔧 **vulkaninfo** - Diagnostic tool to verify Vulkan setup
- 🐳 **Docker Ready** - Pre-configured ICD paths for container passthrough
- 📊 **Web UI** - Status page showing GPU and Vulkan information

## Requirements

- Unraid 6.10.0 or later
- NVIDIA GPU with Vulkan support
- [NVIDIA Driver Plugin](https://forums.unraid.net/topic/98978-plugin-nvidia-driver/) installed

## Installation

### Via Community Applications (Recommended)

1. Open the **Apps** tab in Unraid
2. Search for "Vulkan"
3. Click **Install**

### Manual Installation

```bash
# Install the plugin
plugin install https://raw.githubusercontent.com/Martynyuu/unraid-vulkan/main/vulkan.plg
```

## Usage

### Verify Installation

Open a terminal and run:

```bash
vulkaninfo --summary
```

You should see your NVIDIA GPU listed with Vulkan capabilities.

### Docker Containers

To enable Vulkan in your Docker containers, add these parameters:

```bash
docker run -it \
  --gpus all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
  -v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro \
  your-image
```

### Example: RealityScan Docker

```bash
docker run -it --gpus all \
  -e DISPLAY=$DISPLAY \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
  -v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro \
  -v /mnt/user/scans:/mnt/scans \
  --device /dev/dri \
  ubuntu-realityscan
```

## Web UI

After installation, find **Vulkan Support** under **Settings → Utilities** in the Unraid web interface. The page shows:

- NVIDIA driver status
- Vulkan availability
- GPU information
- Docker mount instructions

## Troubleshooting

### "Cannot create Vulkan instance"

1. Ensure NVIDIA drivers are installed: `nvidia-smi`
2. Check ICD configuration exists: `ls /etc/vulkan/icd.d/`
3. Verify Vulkan libraries: `ldconfig -p | grep vulkan`

### Docker container can't find Vulkan

Make sure you're passing all required mounts:

```bash
-v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro
-v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro
```

### vulkaninfo shows no devices

1. Check NVIDIA driver: `nvidia-smi`
2. Verify nouveau is not loaded: `lsmod | grep nouveau`
3. Ensure GPU supports Vulkan (most GPUs from 2014+ do)

## Building from Source

```bash
# Clone the repository
git clone https://github.com/Martynyuu/unraid-vulkan.git
cd unraid-vulkan

# Build the package
./build.sh

# The .txz package will be in the packages/ directory
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- [Vulkan SDK](https://vulkan.lunarg.com/) by LunarG
- Unraid plugin community for documentation
- [ich777](https://github.com/ich777) for plugin examples

## Support

- [GitHub Issues](https://github.com/Martynyuu/unraid-vulkan/issues)
- [Unraid Forums](https://forums.unraid.net/)
- If this project was helpful consider buying me a [hot chocolate](https://ko-fi.com/strudel9) 
