#!/bin/bash
#
# Build script for Unraid Vulkan plugin package
#
# Downloads vulkaninfo from LunarG SDK and packages for Unraid.
#

set -e

VERSION="${1:-2026.03.02}"
PACKAGE_NAME="vulkan-${VERSION}"
BUILD_DIR="$(pwd)/build"
PACKAGES_DIR="$(pwd)/packages"

# LunarG SDK version (use latest stable)
SDK_VERSION="1.3.296.0"

echo "=========================================="
echo " Building Vulkan Package for Unraid"
echo " Version: ${VERSION}"
echo " SDK: ${SDK_VERSION}"
echo "=========================================="
echo ""

# Clean and create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/install"
mkdir -p "${PACKAGES_DIR}"

# Create package directory structure
mkdir -p "${BUILD_DIR}/usr/bin"
mkdir -p "${BUILD_DIR}/usr/lib64"
mkdir -p "${BUILD_DIR}/usr/share/vulkan"
mkdir -p "${BUILD_DIR}/etc/vulkan/icd.d"

# Download vulkan tools from Ubuntu packages (most compatible)
echo "Downloading Vulkan components..."
TEMP_DIR=$(mktemp -d)
cd "${TEMP_DIR}"

# Ubuntu jammy (22.04) packages work well on Unraid
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu/pool/universe/v"

# vulkan-tools contains vulkaninfo
echo "  Fetching vulkan-tools..."
VULKAN_TOOLS_DEB="vulkan-tools_1.3.204.1-2_amd64.deb"
if wget -q "${UBUNTU_MIRROR}/vulkan-tools/${VULKAN_TOOLS_DEB}" -O vulkan-tools.deb; then
    ar x vulkan-tools.deb
    tar xf data.tar.* -C "${BUILD_DIR}"
    echo "    ✓ vulkan-tools"
else
    echo "    ✗ Failed to download vulkan-tools"
fi

# libvulkan1 contains the loader
echo "  Fetching libvulkan1..."
LIBVULKAN_DEB="libvulkan1_1.3.204.1-2_amd64.deb"
if wget -q "${UBUNTU_MIRROR}/vulkan-loader/${LIBVULKAN_DEB}" -O libvulkan1.deb; then
    ar x libvulkan1.deb
    tar xf data.tar.* -C "${BUILD_DIR}"
    echo "    ✓ libvulkan1"
else
    echo "    ✗ Failed to download libvulkan1"
fi

cd - > /dev/null
rm -rf "${TEMP_DIR}"

# Reorganize files for Slackware/Unraid
if [ -d "${BUILD_DIR}/usr/lib/x86_64-linux-gnu" ]; then
    mv "${BUILD_DIR}/usr/lib/x86_64-linux-gnu"/* "${BUILD_DIR}/usr/lib64/" 2>/dev/null || true
    rm -rf "${BUILD_DIR}/usr/lib/x86_64-linux-gnu"
fi
rm -rf "${BUILD_DIR}/usr/lib" 2>/dev/null || true
rm -rf "${BUILD_DIR}/usr/share/doc" "${BUILD_DIR}/usr/share/man" "${BUILD_DIR}/usr/share/lintian" 2>/dev/null || true

# Verify critical files
echo ""
echo "Verifying files..."
if [ -f "${BUILD_DIR}/usr/bin/vulkaninfo" ]; then
    echo "  ✓ vulkaninfo found"
    chmod +x "${BUILD_DIR}/usr/bin/vulkaninfo"
else
    echo "  ✗ vulkaninfo NOT found"
fi

if ls "${BUILD_DIR}/usr/lib64/libvulkan"* &>/dev/null 2>&1; then
    echo "  ✓ libvulkan found"
else
    echo "  ✗ libvulkan NOT found"
fi

# Create package metadata
cat > "${BUILD_DIR}/install/slack-desc" <<EOF
vulkan: Vulkan Support for Unraid
vulkan:
vulkan: Provides Vulkan loader and tools for NVIDIA GPUs.
vulkan: Run 'vulkaninfo --summary' to verify.
vulkan:
vulkan: https://github.com/Martynyuu/unraid-vulkan
EOF

cat > "${BUILD_DIR}/install/doinst.sh" <<'EOF'
#!/bin/bash
ldconfig 2>/dev/null || true
chmod +x /usr/bin/vulkaninfo 2>/dev/null || true
EOF

# Create the package
echo ""
echo "Creating package..."
cd "${BUILD_DIR}"
tar cJf "${PACKAGES_DIR}/${PACKAGE_NAME}.txz" .

# Generate checksums
cd "${PACKAGES_DIR}"
md5sum "${PACKAGE_NAME}.txz" > "${PACKAGE_NAME}.txz.md5"
sha256sum "${PACKAGE_NAME}.txz" > "${PACKAGE_NAME}.txz.sha256"

SIZE=$(du -h "${PACKAGE_NAME}.txz" | cut -f1)
MD5=$(cat "${PACKAGE_NAME}.txz.md5" | cut -d' ' -f1)

echo ""
echo "=========================================="
echo " Build complete!"
echo ""
echo " Package: ${PACKAGE_NAME}.txz (${SIZE})"
echo " MD5:     ${MD5}"
echo "=========================================="
