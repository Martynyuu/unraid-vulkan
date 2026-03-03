#!/bin/bash
#
# Build script for Unraid Vulkan plugin package
#
# Downloads vulkaninfo and libvulkan from Ubuntu and packages for Unraid.
#

set -e

VERSION="${1:-2026.03.02}"
PACKAGE_NAME="vulkan-${VERSION}"
BUILD_DIR="$(pwd)/build"
PACKAGES_DIR="$(pwd)/packages"

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
mkdir -p "${BUILD_DIR}/usr/share/vulkan"
mkdir -p "${BUILD_DIR}/etc/vulkan/icd.d"

# Download from Ubuntu mirrors (verified working URLs)
echo "Downloading Vulkan components from Ubuntu..."
TEMP_DIR=$(mktemp -d)
cd "${TEMP_DIR}"

# vulkan-tools (contains vulkaninfo)
VULKAN_TOOLS_URL="http://mirrors.kernel.org/ubuntu/pool/universe/v/vulkan-tools/vulkan-tools_1.3.204.0+dfsg1-1_amd64.deb"
echo "  Downloading vulkan-tools..."
if wget -q --timeout=60 "${VULKAN_TOOLS_URL}" -O vulkan-tools.deb; then
    SIZE=$(stat -c%s vulkan-tools.deb 2>/dev/null || stat -f%z vulkan-tools.deb 2>/dev/null)
    echo "    Downloaded: ${SIZE} bytes"
    ar x vulkan-tools.deb
    tar xf data.tar.* -C "${BUILD_DIR}" 2>/dev/null || tar xf data.tar.* -C "${BUILD_DIR}"
    echo "    ✓ vulkan-tools extracted"
else
    echo "    ✗ Failed to download vulkan-tools"
fi

# libvulkan1 (contains the Vulkan loader)
LIBVULKAN_URL="http://mirrors.kernel.org/ubuntu/pool/main/v/vulkan-loader/libvulkan1_1.3.204.1-2_amd64.deb"
echo "  Downloading libvulkan1..."
if wget -q --timeout=60 "${LIBVULKAN_URL}" -O libvulkan1.deb; then
    SIZE=$(stat -c%s libvulkan1.deb 2>/dev/null || stat -f%z libvulkan1.deb 2>/dev/null)
    echo "    Downloaded: ${SIZE} bytes"
    ar x libvulkan1.deb
    tar xf data.tar.* -C "${BUILD_DIR}" 2>/dev/null || tar xf data.tar.* -C "${BUILD_DIR}"
    echo "    ✓ libvulkan1 extracted"
else
    echo "    ✗ Failed to download libvulkan1"
fi

cd - > /dev/null
rm -rf "${TEMP_DIR}"

# Reorganize for Slackware/Unraid (lib path differences)
if [ -d "${BUILD_DIR}/usr/lib/x86_64-linux-gnu" ]; then
    cp -a "${BUILD_DIR}/usr/lib/x86_64-linux-gnu"/* "${BUILD_DIR}/usr/lib64/" 2>/dev/null || true
    rm -rf "${BUILD_DIR}/usr/lib"
fi

# Clean up unnecessary files
rm -rf "${BUILD_DIR}/usr/share/doc" "${BUILD_DIR}/usr/share/man" "${BUILD_DIR}/usr/share/lintian" 2>/dev/null || true
rm -rf "${BUILD_DIR}/usr/share/bug" 2>/dev/null || true

# Verify critical files
echo ""
echo "Verifying installed files..."
if [ -f "${BUILD_DIR}/usr/bin/vulkaninfo" ]; then
    echo "  ✓ vulkaninfo found"
    chmod +x "${BUILD_DIR}/usr/bin/vulkaninfo"
else
    echo "  ✗ vulkaninfo NOT found - build failed"
    exit 1
fi

if ls "${BUILD_DIR}/usr/lib64/libvulkan.so"* &>/dev/null 2>&1; then
    echo "  ✓ libvulkan found"
    ls -la "${BUILD_DIR}/usr/lib64/libvulkan"* 2>/dev/null | head -3
else
    echo "  ⚠ libvulkan not found (may still work with system libs)"
fi

# Create package metadata
cat > "${BUILD_DIR}/install/slack-desc" <<EOF
vulkan: Vulkan Support for Unraid
vulkan:
vulkan: Provides Vulkan loader and tools (vulkaninfo) for GPU support.
vulkan: Run 'vulkaninfo --summary' to verify installation.
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

# Show what's in the package
echo ""
echo "Package contents:"
tar -tf "${PACKAGE_NAME}.txz" | grep -E "(vulkaninfo|libvulkan)" | head -10
