#!/usr/bin/env bash
# Shared staging/packaging helpers for packages/<app>/build.sh scripts.
# Sourced (not executed) -- each function reads/writes globals the caller
# is expected to have set (SCRIPT_DIR, SHARED_DIR, WORK_DIR, STAGE_DIR,
# PAYLOAD_DIR, VERSION, OUT_DIR), matching how the rest of each build.sh
# already threads those paths through. Everything here is the part of the
# recipe that's identical across every package -- app-specific bits (source
# fetch, build flags, INFO fields) stay in each package's own build.sh.

# Parses --version/--os-min-ver/--out into VERSION/OS_MIN_VER/OUT_DIR.
# Requires SCRIPT_DIR set by the caller. Exits 1 on unknown arg or missing
# --version.
spk_parse_build_args() {
    OS_MIN_VER="7.0-40000"
    OUT_DIR="${SCRIPT_DIR}/dist"
    VERSION=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --os-min-ver)
                OS_MIN_VER="$2"
                shift 2
                ;;
            --out)
                OUT_DIR="$2"
                shift 2
                ;;
            *)
                echo "unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ -z "${VERSION}" ]; then
        echo "usage: $(basename "$0") --version X.Y.Z [--os-min-ver 7.0-40000] [--out DIR]" >&2
        exit 1
    fi
}

# Populates STAGE_DIR with package.tgz (binary + conf.ini), the generic
# DSM7 lifecycle scripts vendored in SHARED_DIR plus this package's own
# service-setup, and the conf/wizard trees. Requires SCRIPT_DIR, SHARED_DIR,
# STAGE_DIR, PAYLOAD_DIR set by the caller.
# Args: BINARY_PATH BINARY_DEST_NAME
spk_stage_package() {
    local binary_path="$1"
    local binary_dest_name="$2"

    mkdir -p "${STAGE_DIR}" "${PAYLOAD_DIR}/bin" "${PAYLOAD_DIR}/var"
    cp "${binary_path}" "${PAYLOAD_DIR}/bin/${binary_dest_name}"
    chmod +x "${PAYLOAD_DIR}/bin/${binary_dest_name}"
    cp "${SCRIPT_DIR}/src/conf.ini" "${PAYLOAD_DIR}/var/conf.ini"
    tar czf "${STAGE_DIR}/package.tgz" -C "${PAYLOAD_DIR}" bin var

    mkdir -p "${STAGE_DIR}/scripts"
    cp "${SHARED_DIR}/"* "${STAGE_DIR}/scripts/"
    rm -f "${STAGE_DIR}/scripts/NOTICE.md"
    cp "${SCRIPT_DIR}/src/scripts/service-setup" "${STAGE_DIR}/scripts/service-setup"
    chmod +x "${STAGE_DIR}/scripts/"preinst "${STAGE_DIR}/scripts/"postinst \
        "${STAGE_DIR}/scripts/"preuninst "${STAGE_DIR}/scripts/"postuninst \
        "${STAGE_DIR}/scripts/"preupgrade "${STAGE_DIR}/scripts/"postupgrade \
        "${STAGE_DIR}/scripts/"start-stop-status "${STAGE_DIR}/scripts/"installer.dsm7

    cp -R "${SCRIPT_DIR}/src/conf" "${STAGE_DIR}/conf"
    cp -R "${SCRIPT_DIR}/src/wizard" "${STAGE_DIR}/wizard"
}

# Tars STAGE_DIR (which must already contain INFO, written by the caller)
# into the final .spk under OUT_DIR. Requires OUT_DIR, STAGE_DIR, VERSION
# set by the caller.
# Args: PACKAGE_NAME
spk_write_archive() {
    local package_name="$1"

    mkdir -p "${OUT_DIR}"
    SPK_PATH="${OUT_DIR}/${package_name}-${VERSION}-x86_64.spk"
    tar cf "${SPK_PATH}" -C "${STAGE_DIR}" INFO package.tgz scripts conf wizard
    echo "wrote ${SPK_PATH}"
}
