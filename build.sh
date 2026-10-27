#!/bin/bash
#
# Build the Slackware package for the Unraid Vulkan plugin.
#
# Builds the Vulkan loader (libvulkan.so.1) and vulkaninfo from the
# Khronos sources at a pinned Vulkan SDK tag and packages them, together
# with the plugin's web page and ICD helper script (source/), as
#
#     packages/vulkan-<version>-x86_64-<build>.txz
#
# The binaries link against the glibc of the build machine. Unraid 6.10
# ships glibc 2.33, so build on a distribution with glibc <= 2.33
# (the release workflow uses ubuntu:20.04, glibc 2.31). The script
# refuses to package binaries that need a newer glibc than GLIBC_MAX.
#
# Usage:   ./build.sh [version]
#
#   version             package version, default: pkgversion entity in vulkan.plg
#
# Environment:
#   VULKAN_SDK_VERSION  Khronos tag to build, default: vulkansdk entity in vulkan.plg
#   BUILD               Slackware build number (default 1)
#   GLIBC_MAX           newest glibc symbol version allowed (default 2.33)
#   JOBS                parallel compile jobs (default: nproc)
#
# Requires: bash, git, a C/C++17 compiler, make, tar, xz, objdump, curl.
# CMake >= 3.22.1 is used from PATH or downloaded (pinned + sha256-checked).
#

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_DIR}"

plg_entity() {
    sed -n "s/.*<!ENTITY[[:space:]]\{1,\}$1[[:space:]]\{1,\}\"\([^\"]*\)\".*/\1/p" "${REPO_DIR}/vulkan.plg" | head -n1
}

VERSION="${1:-$(plg_entity pkgversion)}"
VULKAN_SDK_VERSION="${VULKAN_SDK_VERSION:-$(plg_entity vulkansdk)}"
BUILD="${BUILD:-1}"
ARCH="x86_64"
GLIBC_MAX="${GLIBC_MAX:-2.33}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

PKGNAME="vulkan-${VERSION}-${ARCH}-${BUILD}"
WORK_DIR="${REPO_DIR}/build"
SRC_DIR="${WORK_DIR}/src"
PKG_DIR="${WORK_DIR}/package"
STAGE_DIR="${WORK_DIR}/stage"
OUT_DIR="${REPO_DIR}/packages"

CMAKE_PIN_VERSION="3.31.8"
CMAKE_PIN_SHA256="630615d8e98ac33eba7fbe472626dff5c899c85af3c024585ae109166a6909d0"

die() { echo "ERROR: $*" >&2; exit 1; }

# Slackware package names are name-version-arch-build: no '-' inside fields.
[[ -n "${VERSION}" && "${VERSION}" != *-* ]] || die "invalid version '${VERSION}' (must be non-empty, no '-')"
[[ "${VULKAN_SDK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "invalid VULKAN_SDK_VERSION '${VULKAN_SDK_VERSION}'"
[[ "${BUILD}" =~ ^[0-9]+[a-z_]*$ ]] || die "invalid BUILD '${BUILD}'"

for tool in git cc c++ make tar xz objdump curl sha256sum md5sum; do
    command -v "${tool}" >/dev/null 2>&1 || die "'${tool}' not found"
done

echo "=========================================="
echo " Building ${PKGNAME}.txz"
echo " Vulkan SDK tag: vulkan-sdk-${VULKAN_SDK_VERSION}"
echo " glibc limit:    ${GLIBC_MAX} (build host: $(ldd --version 2>/dev/null | head -n1 | awk '{print $NF}'))"
echo "=========================================="

rm -rf "${PKG_DIR}" "${STAGE_DIR}" "${WORK_DIR}"/cmake-*-build
mkdir -p "${SRC_DIR}" "${PKG_DIR}" "${STAGE_DIR}" "${OUT_DIR}"

# --- CMake --------------------------------------------------------------------
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

CMAKE="$(command -v cmake || true)"
if [ -z "${CMAKE}" ] || ! version_ge "$("${CMAKE}" --version | head -n1 | awk '{print $3}')" 3.22.1; then
    CMAKE="${WORK_DIR}/tools/cmake-${CMAKE_PIN_VERSION}-linux-x86_64/bin/cmake"
    if [ ! -x "${CMAKE}" ]; then
        echo "Downloading CMake ${CMAKE_PIN_VERSION}..."
        mkdir -p "${WORK_DIR}/tools"
        TARBALL="${WORK_DIR}/tools/cmake-${CMAKE_PIN_VERSION}-linux-x86_64.tar.gz"
        curl -fsSL -o "${TARBALL}" \
            "https://github.com/Kitware/CMake/releases/download/v${CMAKE_PIN_VERSION}/cmake-${CMAKE_PIN_VERSION}-linux-x86_64.tar.gz"
        echo "${CMAKE_PIN_SHA256}  ${TARBALL}" | sha256sum -c --quiet - || die "CMake checksum mismatch"
        tar -xzf "${TARBALL}" -C "${WORK_DIR}/tools"
    fi
fi
echo "Using $("${CMAKE}" --version | head -n1)"

# --- Sources ------------------------------------------------------------------
fetch() {
    local repo="$1" dir="${SRC_DIR}/$1-${VULKAN_SDK_VERSION}"
    if [ ! -d "${dir}/.git" ]; then
        echo "Cloning ${repo} @ vulkan-sdk-${VULKAN_SDK_VERSION}..."
        git -c advice.detachedHead=false clone --quiet --depth 1 \
            --branch "vulkan-sdk-${VULKAN_SDK_VERSION}" \
            "https://github.com/KhronosGroup/${repo}.git" "${dir}"
    fi
}
fetch Vulkan-Headers
fetch Vulkan-Loader
fetch Vulkan-Tools

COMMON_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    -DCMAKE_INSTALL_LIBDIR=lib64
    -DCMAKE_INSTALL_SYSCONFDIR=/etc
    -DCMAKE_INSTALL_DATADIR=share
    -DBUILD_TESTS=OFF
    # Headless host: no window-system support, no X11/Wayland runtime deps.
    -DBUILD_WSI_XCB_SUPPORT=OFF
    -DBUILD_WSI_XLIB_SUPPORT=OFF
    -DBUILD_WSI_WAYLAND_SUPPORT=OFF
    -DBUILD_WSI_DIRECTFB_SUPPORT=OFF
)

build_one() {
    local name="$1" src="$2" dest="$3"; shift 3
    local bdir="${WORK_DIR}/cmake-${name}-build"
    "${CMAKE}" -S "${src}" -B "${bdir}" "${COMMON_FLAGS[@]}" "$@" >"${WORK_DIR}/${name}-configure.log" 2>&1 \
        || { tail -n 40 "${WORK_DIR}/${name}-configure.log"; die "configure ${name} failed"; }
    "${CMAKE}" --build "${bdir}" --parallel "${JOBS}" >"${WORK_DIR}/${name}-build.log" 2>&1 \
        || { tail -n 40 "${WORK_DIR}/${name}-build.log"; die "build ${name} failed"; }
    DESTDIR="${dest}" "${CMAKE}" --install "${bdir}" >/dev/null
    echo "  built ${name}"
}

echo "Building..."
# Headers and loader go to a staging root first; tools build against it.
build_one headers "${SRC_DIR}/Vulkan-Headers-${VULKAN_SDK_VERSION}" "${STAGE_DIR}"
build_one loader  "${SRC_DIR}/Vulkan-Loader-${VULKAN_SDK_VERSION}"  "${STAGE_DIR}" \
    -DCMAKE_PREFIX_PATH="${STAGE_DIR}/usr"
build_one tools   "${SRC_DIR}/Vulkan-Tools-${VULKAN_SDK_VERSION}"   "${STAGE_DIR}" \
    -DCMAKE_PREFIX_PATH="${STAGE_DIR}/usr" \
    -DBUILD_CUBE=OFF -DBUILD_VULKANINFO=ON -DBUILD_ICD=ON \
    -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"

# --- Assemble package root ------------------------------------------------------
echo "Assembling package..."
install -d -m 0755 "${PKG_DIR}/usr/bin" "${PKG_DIR}/usr/lib64" "${PKG_DIR}/install" \
    "${PKG_DIR}/usr/doc/${PKGNAME%-"${ARCH}"-*}"

install -m 0755 "${STAGE_DIR}/usr/bin/vulkaninfo" "${PKG_DIR}/usr/bin/vulkaninfo"
# Loader: real file + SONAME link only (no headers, no dev symlink).
LOADER_REAL="$(cd "${STAGE_DIR}/usr/lib64" && ls libvulkan.so.1.* | head -n1)"
[ -n "${LOADER_REAL}" ] || die "loader library not found in stage"
install -m 0755 "${STAGE_DIR}/usr/lib64/${LOADER_REAL}" "${PKG_DIR}/usr/lib64/${LOADER_REAL}"
ln -sf "${LOADER_REAL}" "${PKG_DIR}/usr/lib64/libvulkan.so.1"
strip --strip-unneeded "${PKG_DIR}/usr/bin/vulkaninfo" "${PKG_DIR}/usr/lib64/${LOADER_REAL}"

# Plugin files (web page, ICD helper).
cp -a "${REPO_DIR}/source/." "${PKG_DIR}/"
find "${PKG_DIR}/usr/local" -type d -exec chmod 0755 {} +
find "${PKG_DIR}/usr/local" -type f -exec chmod 0644 {} +
chmod 0755 "${PKG_DIR}"/usr/local/emhttp/plugins/vulkan/scripts/*

install -m 0644 "${SRC_DIR}/Vulkan-Loader-${VULKAN_SDK_VERSION}/LICENSE.txt" \
    "${PKG_DIR}/usr/doc/${PKGNAME%-"${ARCH}"-*}/LICENSE.Vulkan-Loader"
install -m 0644 "${SRC_DIR}/Vulkan-Tools-${VULKAN_SDK_VERSION}/LICENSE.txt" \
    "${PKG_DIR}/usr/doc/${PKGNAME%-"${ARCH}"-*}/LICENSE.Vulkan-Tools"
echo "${VULKAN_SDK_VERSION}" > "${PKG_DIR}/usr/local/emhttp/plugins/vulkan/VULKAN_SDK_VERSION"

# slack-desc: exactly 11 "vulkan:" lines, max 70 chars of text each.
cat > "${PKG_DIR}/install/slack-desc" <<EOF
      |-----handy-ruler------------------------------------------------------|
vulkan: vulkan (Vulkan loader and vulkaninfo for Unraid)
vulkan:
vulkan: Vulkan loader (libvulkan.so.1) and vulkaninfo built from the Khronos
vulkan: sources, Vulkan SDK ${VULKAN_SDK_VERSION}, plus the Unraid plugin page and the
vulkan: NVIDIA ICD helper. Run 'vulkaninfo --summary' to verify.
vulkan:
vulkan:
vulkan:
vulkan:
vulkan: https://github.com/Martynyuu/unraid-vulkan
EOF

cat > "${PKG_DIR}/install/doinst.sh" <<'EOF'
if [ -x /sbin/ldconfig ]; then
  /sbin/ldconfig 2>/dev/null
fi
EOF

# --- Portability checks ---------------------------------------------------------
echo ""
echo "Checking binaries..."
ELF_FILES=("${PKG_DIR}/usr/bin/vulkaninfo" "${PKG_DIR}/usr/lib64/${LOADER_REAL}")
MAX_GLIBC="$(objdump -T "${ELF_FILES[@]}" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -Vu | tail -n1)"
echo "  newest glibc symbol: GLIBC_${MAX_GLIBC} (limit ${GLIBC_MAX})"
version_ge "${GLIBC_MAX}" "${MAX_GLIBC}" \
    || die "binaries need GLIBC_${MAX_GLIBC} > ${GLIBC_MAX}; build on an older distro (e.g. ubuntu:20.04)"
for f in "${ELF_FILES[@]}"; do
    echo "  $(basename "$f") needs: $(objdump -p "$f" | awk '/NEEDED/{printf "%s ", $2}')"
    if objdump -p "$f" | awk '/NEEDED/{print $2}' | grep -qvE '^(libc|libm|libdl|libpthread|librt|ld-linux-x86-64|libvulkan)\.so'; then
        die "$(basename "$f") links an unexpected library"
    fi
done

# Smoke test: run the packaged vulkaninfo + loader against the Khronos mock ICD
# (built in the tools tree; neither installed nor packaged).
MOCK_JSON="$(find "${WORK_DIR}/cmake-tools-build" -name 'VkICD_mock_icd.json' | head -n1)"
if [ -n "${MOCK_JSON}" ]; then
    if OUT="$(LD_LIBRARY_PATH="${PKG_DIR}/usr/lib64" \
              VK_DRIVER_FILES="${MOCK_JSON}" VK_ICD_FILENAMES="${MOCK_JSON}" \
              timeout 30 "${PKG_DIR}/usr/bin/vulkaninfo" --summary 2>&1)"; then
        echo "${OUT}" | grep -E 'Vulkan Instance Version|apiVersion|deviceName|driverName' | sed 's/^/  mock: /'
    else
        echo "${OUT}" | tail -n 20
        die "vulkaninfo smoke test against the mock ICD failed"
    fi
else
    echo "  (mock ICD not built - smoke test skipped)"
fi

# --- Package --------------------------------------------------------------------
echo ""
echo "Creating package..."
rm -f "${OUT_DIR}/${PKGNAME}.txz"*
if [ -x /sbin/makepkg ]; then
    (cd "${PKG_DIR}" && /sbin/makepkg -l y -c n "${OUT_DIR}/${PKGNAME}.txz" >/dev/null)
else
    # Same layout makepkg produces; sorted, root-owned, fixed mtime.
    MTIME="@${SOURCE_DATE_EPOCH:-$(git -C "${REPO_DIR}" log -1 --format=%ct 2>/dev/null || date +%s)}"
    tar -C "${PKG_DIR}" --sort=name --mtime="${MTIME}" \
        --owner=0 --group=0 --numeric-owner -cf - . \
        | xz -9 -T1 -c > "${OUT_DIR}/${PKGNAME}.txz"
fi

cd "${OUT_DIR}"
md5sum "${PKGNAME}.txz" > "${PKGNAME}.txz.md5"
sha256sum "${PKGNAME}.txz" > "${PKGNAME}.txz.sha256"

echo ""
echo "=========================================="
echo " Build complete"
echo " Package: packages/${PKGNAME}.txz ($(du -h "${PKGNAME}.txz" | cut -f1))"
echo " MD5:     $(cut -d' ' -f1 "${PKGNAME}.txz.md5")"
echo " Loader:  ${LOADER_REAL}"
echo " glibc:   GLIBC_${MAX_GLIBC} max"
echo "=========================================="
tar -tJf "${PKGNAME}.txz" | sed 's/^/  /'
