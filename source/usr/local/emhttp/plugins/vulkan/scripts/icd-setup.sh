#!/bin/bash
#
# Configure the NVIDIA Vulkan ICD manifest on the Unraid host.
#
#   1. Clean up what plugin versions <= 2026.03.02b left behind (hard-coded
#      /etc manifest, /usr/share symlink, /etc/profile.d/vulkan.sh).
#   2. If the NVIDIA driver ships its own nvidia_icd*.json, use it untouched.
#   3. Otherwise generate /etc/vulkan/icd.d/nvidia_icd.json (marked as ours)
#      and probe the real API version with vulkaninfo.
#
# The result is written to $STATE for the web page.
#
# Usage: icd-setup.sh [install|remove]
#
# VULKAN_ROOT relocates every path (used for testing on non-Unraid hosts).

R="${VULKAN_ROOT:-}"
ETC_ICD="${R}/etc/vulkan/icd.d"
SHARE_ICD="${R}/usr/share/vulkan/icd.d"
GENERATED="${ETC_ICD}/nvidia_icd.json"
MARKER="${R}/etc/vulkan/unraid-vulkan.generated"   # outside icd.d: the loader never reads it
STATE_DIR="${R}/var/local/emhttp/plugins/vulkan"
STATE="${STATE_DIR}/icd.state"
PROFILE="${R}/etc/profile.d/vulkan.sh"
LIB="libGLX_nvidia.so.0"

say() { echo " $*"; }

# Content written by plugin versions <= 2026.03.02b (compared without whitespace).
LEGACY_JSON='{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3"}}'
squash() { tr -d ' \t\r\n' < "$1" 2>/dev/null; }

remove_ours() {
    if [ -f "${MARKER}" ]; then
        rm -f "${GENERATED}" "${MARKER}"
    fi
    # Legacy: symlink /usr/share/... -> /etc/... created by old versions.
    if [ -L "${SHARE_ICD}/nvidia_icd.json" ] && \
       [ "$(readlink "${SHARE_ICD}/nvidia_icd.json")" = "/etc/vulkan/icd.d/nvidia_icd.json" ]; then
        rm -f "${SHARE_ICD}/nvidia_icd.json"
    fi
    # Legacy: hard-coded manifest without marker.
    if [ -f "${GENERATED}" ] && [ ! -L "${GENERATED}" ] && [ "$(squash "${GENERATED}")" = "${LEGACY_JSON}" ]; then
        rm -f "${GENERATED}"
    fi
    # Legacy: global VK_ICD_FILENAMES export (hid every other ICD on the host).
    if [ -f "${PROFILE}" ] && grep -q 'VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json' "${PROFILE}"; then
        rm -f "${PROFILE}"
    fi
}

find_lib() {
    local d
    for d in /usr/lib64 /usr/lib /usr/lib/x86_64-linux-gnu /lib64; do
        if [ -e "${R}${d}/${LIB}" ]; then echo "${R}${d}/${LIB}"; return 0; fi
    done
    if [ -z "${R}" ] && command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | awk -v l="${LIB}" '$1==l {print $NF; exit}' | grep . && return 0
    fi
    return 1
}

find_driver_manifest() {
    local f
    for f in "${ETC_ICD}"/nvidia_icd*.json "${SHARE_ICD}"/nvidia_icd*.json; do
        [ -e "$f" ] || continue
        [ "$f" = "${GENERATED}" ] && [ -f "${MARKER}" ] && continue
        echo "$f"; return 0
    done
    return 1
}

write_manifest() {
    cat > "${GENERATED}" <<EOF
{
    "file_format_version": "1.0.1",
    "ICD": {
        "library_path": "${LIB}",
        "api_version": "$1"
    }
}
EOF
    chmod 0644 "${GENERATED}"
}

write_state() {
    mkdir -p "${STATE_DIR}"
    {
        echo "SOURCE=\"$1\""
        echo "MANIFEST=\"$2\""
        echo "LIBRARY=\"$3\""
        echo "API_VERSION=\"$4\""
        echo "UPDATED=\"$(date '+%Y-%m-%d %H:%M:%S')\""
    } > "${STATE}"
}

install_icd() {
    mkdir -p "${ETC_ICD}"
    remove_ours

    local libpath manifest api
    libpath="$(find_lib || true)"

    if manifest="$(find_driver_manifest)"; then
        api="$(sed -n 's/.*"api_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${manifest}" | head -n1)"
        say "Using the NVIDIA driver's ICD manifest: ${manifest#"${R}"}"
        write_state driver "${manifest#"${R}"}" "${libpath#"${R}"}" "${api}"
    else
        # api_version is informational for the loader; the driver reports the
        # real version. Start conservative, then ask the driver if it is there.
        api="1.3.0"
        write_manifest "${api}"
        echo "${GENERATED}" > "${MARKER}"
        if [ -n "${libpath}" ] && [ -z "${R}" ] && command -v vulkaninfo >/dev/null 2>&1; then
            probed="$(VK_DRIVER_FILES="${GENERATED}" VK_ICD_FILENAMES="${GENERATED}" \
                timeout 15 vulkaninfo --summary 2>/dev/null \
                | sed -n 's/^[[:space:]]*apiVersion[[:space:]]*=[^0-9]*\([0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\).*/\1/p' | head -n1)"
            if [ -n "${probed}" ]; then
                api="${probed}"
                write_manifest "${api}"
            fi
        fi
        say "No ICD manifest from the NVIDIA driver found - generated ${GENERATED#"${R}"} (api ${api})"
        write_state generated "${GENERATED#"${R}"}" "${libpath#"${R}"}" "${api}"
    fi

    if [ -z "${libpath}" ]; then
        say "WARNING: ${LIB} not found - is the NVIDIA Driver plugin installed?"
        say "         Vulkan will not see the NVIDIA GPU until the driver is installed"
        say "         (then reboot or reinstall this plugin)."
    fi
}

case "${1:-install}" in
    install) install_icd ;;
    remove)  remove_ours; rm -rf "${STATE_DIR}" ;;
    *) echo "usage: $0 [install|remove]" >&2; exit 2 ;;
esac
exit 0
