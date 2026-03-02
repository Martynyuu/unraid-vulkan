#!/bin/bash
#
# Build script for Unraid Vulkan plugin package
#
# This script downloads Vulkan libraries from Slackware and packages them
# for Unraid installation.
#

set -e

VERSION="${1:-2026.03.02}"
PACKAGE_NAME="vulkan-${VERSION}"
BUILD_DIR="$(pwd)/build"
PACKAGES_DIR="$(pwd)/packages"
SRC_DIR="$(pwd)/src"

# Slackware mirror and package info
SLACKWARE_MIRROR="https://mirrors.slackware.com/slackware/slackware64-current/slackware64"

# Required packages from Slackware
VULKAN_PACKAGES=(
    "l/Vulkan-Headers"
    "l/Vulkan-Loader"  
    "l/Vulkan-Tools"
    "l/vulkan-extensionlayer"
    "l/vulkan-validationlayers"
    "l/spirv-headers"
    "l/spirv-tools"
    "l/glslang"
)

echo "=========================================="
echo " Building Vulkan Package for Unraid"
echo " Version: ${VERSION}"
echo "=========================================="
echo ""

# Clean and create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/install"
mkdir -p "${PACKAGES_DIR}"

# Create package directory structure
mkdir -p "${BUILD_DIR}/usr/bin"
mkdir -p "${BUILD_DIR}/usr/lib64"
mkdir -p "${BUILD_DIR}/usr/share/vulkan/icd.d"
mkdir -p "${BUILD_DIR}/usr/share/vulkan/explicit_layer.d"
mkdir -p "${BUILD_DIR}/usr/share/vulkan/implicit_layer.d"
mkdir -p "${BUILD_DIR}/etc/vulkan/icd.d"
mkdir -p "${BUILD_DIR}/usr/local/emhttp/plugins/vulkan"

# Download and extract Slackware packages
echo "Downloading Vulkan packages from Slackware..."
TEMP_DIR=$(mktemp -d)

for pkg_path in "${VULKAN_PACKAGES[@]}"; do
    pkg_name=$(basename "${pkg_path}")
    echo "  Fetching ${pkg_name}..."
    
    # Get package listing to find exact filename
    pkg_url=$(curl -sL "${SLACKWARE_MIRROR}/${pkg_path}/" | grep -oP 'href="[^"]+\.txz"' | head -1 | sed 's/href="//;s/"//')
    
    if [ -n "${pkg_url}" ]; then
        wget -q "${SLACKWARE_MIRROR}/${pkg_path}/${pkg_url}" -O "${TEMP_DIR}/${pkg_url}" 2>/dev/null || {
            echo "    Warning: Could not download ${pkg_name}"
            continue
        }
        
        # Extract to build directory
        cd "${BUILD_DIR}"
        tar xf "${TEMP_DIR}/${pkg_url}" 2>/dev/null || true
        cd - > /dev/null
        echo "    ✓ ${pkg_url}"
    else
        echo "    Warning: Package not found: ${pkg_name}"
    fi
done

rm -rf "${TEMP_DIR}"

# Create package description
cat > "${BUILD_DIR}/install/slack-desc" <<EOF
vulkan: Vulkan Support for Unraid
vulkan:
vulkan: Provides Vulkan loader, tools, and ICD configuration for
vulkan: NVIDIA GPUs on Unraid systems. Required for GPU-accelerated
vulkan: applications like RealityScan in Docker containers.
vulkan:
vulkan: Includes:
vulkan:   - Vulkan Loader (libvulkan)
vulkan:   - Vulkan Tools (vulkaninfo)
vulkan:   - SPIR-V tools
vulkan:
vulkan: https://github.com/Martynyuu/unraid-vulkan
EOF

# Create post-install script
cat > "${BUILD_DIR}/install/doinst.sh" <<'EOF'
#!/bin/bash
# Update library cache
ldconfig 2>/dev/null || true

# Ensure vulkaninfo is executable
chmod +x /usr/bin/vulkaninfo 2>/dev/null || true
EOF

# Remove unnecessary files to reduce package size
rm -rf "${BUILD_DIR}/usr/doc"
rm -rf "${BUILD_DIR}/usr/man"
rm -rf "${BUILD_DIR}/usr/include"
rm -rf "${BUILD_DIR}/usr/lib64/cmake"
rm -rf "${BUILD_DIR}/usr/lib64/pkgconfig"

# Create the package
echo ""
echo "Creating package..."
cd "${BUILD_DIR}"
makepkg -l y -c n "${PACKAGES_DIR}/${PACKAGE_NAME}.txz"

# Generate MD5
cd "${PACKAGES_DIR}"
md5sum "${PACKAGE_NAME}.txz" > "${PACKAGE_NAME}.txz.md5"
sha256sum "${PACKAGE_NAME}.txz" > "${PACKAGE_NAME}.txz.sha256"

echo ""
echo "=========================================="
echo " Build complete!"
echo ""
echo " Package: ${PACKAGES_DIR}/${PACKAGE_NAME}.txz"
echo " MD5:     $(cat ${PACKAGE_NAME}.txz.md5 | cut -d' ' -f1)"
echo " SHA256:  $(cat ${PACKAGE_NAME}.txz.sha256 | cut -d' ' -f1)"
echo "=========================================="
