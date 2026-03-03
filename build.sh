#!/bin/bash
#
# Build script for Unraid Vulkan plugin package
#
# Downloads Vulkan libraries from Slackware and packages them for Unraid.
#

set -e

VERSION="${1:-2026.03.02}"
PACKAGE_NAME="vulkan-${VERSION}"
BUILD_DIR="$(pwd)/build"
PACKAGES_DIR="$(pwd)/packages"

# Slackware 15.0 packages (stable versions that work with Unraid 6.x)
# Using direct URLs to avoid HTML parsing issues
SLACKWARE_BASE="https://mirrors.slackware.com/slackware/slackware64-15.0/slackware64/l"

# Direct package filenames (Slackware 15.0)
declare -A PACKAGES=(
    ["Vulkan-Loader"]="Vulkan-Loader-1.3.204-x86_64-1.txz"
    ["Vulkan-Tools"]="Vulkan-Tools-1.3.204-x86_64-1.txz"
    ["spirv-tools"]="spirv-tools-2022.1-x86_64-1.txz"
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
mkdir -p "${BUILD_DIR}/usr/share/vulkan"
mkdir -p "${BUILD_DIR}/etc/vulkan/icd.d"

# Download and extract packages
echo "Downloading Vulkan packages from Slackware 15.0..."
TEMP_DIR=$(mktemp -d)
DOWNLOAD_OK=0

for pkg_name in "${!PACKAGES[@]}"; do
    pkg_file="${PACKAGES[$pkg_name]}"
    url="${SLACKWARE_BASE}/${pkg_file}"
    
    echo "  ${pkg_name}..."
    echo "    URL: ${url}"
    
    if wget --timeout=30 -q "${url}" -O "${TEMP_DIR}/${pkg_file}"; then
        size=$(stat -f%z "${TEMP_DIR}/${pkg_file}" 2>/dev/null || stat -c%s "${TEMP_DIR}/${pkg_file}" 2>/dev/null || echo "?")
        echo "    Downloaded: ${size} bytes"
        
        if [ "${size}" != "?" ] && [ "${size}" -gt 1000 ]; then
            cd "${BUILD_DIR}"
            tar xf "${TEMP_DIR}/${pkg_file}" 2>/dev/null && echo "    ✓ Extracted" || echo "    ⚠ Extract warning"
            cd - > /dev/null
            DOWNLOAD_OK=$((DOWNLOAD_OK + 1))
        else
            echo "    ⚠ File too small, skipping"
        fi
    else
        echo "    ✗ Download failed"
    fi
done

rm -rf "${TEMP_DIR}"

echo ""
echo "Downloaded ${DOWNLOAD_OK}/${#PACKAGES[@]} packages"

# Verify critical files
echo ""
echo "Checking for critical files..."
VULKANINFO="${BUILD_DIR}/usr/bin/vulkaninfo"
LIBVULKAN="${BUILD_DIR}/usr/lib64/libvulkan.so.1"

if [ -f "${VULKANINFO}" ]; then
    echo "  ✓ vulkaninfo found"
else
    echo "  ✗ vulkaninfo NOT found"
fi

if [ -f "${LIBVULKAN}" ] || ls "${BUILD_DIR}/usr/lib64/libvulkan"* &>/dev/null 2>&1; then
    echo "  ✓ libvulkan found"
else
    echo "  ✗ libvulkan NOT found"
fi

# Create package metadata
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

cat > "${BUILD_DIR}/install/doinst.sh" <<'EOF'
#!/bin/bash
ldconfig 2>/dev/null || true
chmod +x /usr/bin/vulkaninfo 2>/dev/null || true
EOF

# Cleanup unnecessary files
rm -rf "${BUILD_DIR}/usr/doc" "${BUILD_DIR}/usr/man" "${BUILD_DIR}/usr/include"
rm -rf "${BUILD_DIR}/usr/lib64/cmake" "${BUILD_DIR}/usr/lib64/pkgconfig"
rm -rf "${BUILD_DIR}/install/slack-*" 2>/dev/null || true

# Keep only our slack-desc
cat > "${BUILD_DIR}/install/slack-desc" <<EOF
vulkan: Vulkan Support for Unraid
vulkan:
vulkan: https://github.com/Martynyuu/unraid-vulkan
EOF

# Create the package
echo ""
echo "Creating package..."
cd "${BUILD_DIR}"

if command -v makepkg &>/dev/null; then
    makepkg -l y -c n "${PACKAGES_DIR}/${PACKAGE_NAME}.txz"
else
    tar cJf "${PACKAGES_DIR}/${PACKAGE_NAME}.txz" .
fi

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
