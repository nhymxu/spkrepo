#!/usr/bin/env bash
# Build a DSM7 x86_64 .spk for Forgejo (https://codeberg.org/forgejo/forgejo)
# from source, following the same build recipe as the real, maintained
# SynoCommunity/spksrc forgejo package (cross/forgejo/Makefile,
# spk/forgejo/Makefile): fetch Forgejo's own vendored-deps source
# tarball, build with CGO/sqlite/bindata, embed config paths via ldflags,
# and package with the git dependency + dedicated-user + shared-folder
# wizard the real package uses.
#
# Run on an x86_64 Linux host with Go >= 1.24, Node >= 20, `make`, gcc
# (CGO_ENABLED=1) -- no cross-compilation.
#
# Usage:
#   packages/forgejo/build.sh --version 15.0.4 [--os-min-ver 7.0-40000] [--out DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../_shared/spksrc-service"
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
    echo "usage: build.sh --version X.Y.Z [--os-min-ver 7.0-40000] [--out DIR]" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

SRC_DIR="${WORK_DIR}/forgejo-src-${VERSION}"
TARBALL="${WORK_DIR}/forgejo-src-${VERSION}.tar.gz"
TARBALL_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${VERSION}/forgejo-src-${VERSION}.tar.gz"

echo "fetching ${TARBALL_URL} ..." >&2
curl -fsSL "${TARBALL_URL}" -o "${TARBALL}"
mkdir -p "${SRC_DIR}"
tar xzf "${TARBALL}" -C "${SRC_DIR}" --strip-components=1

# Persistent runtime paths, baked into the binary at build time (matches
# cross/forgejo/Makefile) so Forgejo has sane defaults even without the
# env vars start-stop-status also sets.
PKG_VAR="/var/packages/forgejo/var"
LDFLAGS="-X \"forgejo.org/modules/setting.CustomPath=${PKG_VAR}/custom\""
LDFLAGS="${LDFLAGS} -X \"forgejo.org/modules/setting.CustomConf=${PKG_VAR}/conf.ini\""
LDFLAGS="${LDFLAGS} -X \"forgejo.org/modules/setting.AppWorkPath=${PKG_VAR}\""
LDFLAGS="${LDFLAGS} -X \"forgejo.org/modules/setting.PIDFile=${PKG_VAR}/forgejo.pid\""

echo "building (make build, TAGS=bindata timetzdata sqlite sqlite_unlock_notify) ..." >&2
(
    cd "${SRC_DIR}"
    CGO_ENABLED=1 \
    EXTRA_GOFLAGS=-buildvcs=false \
    LDFLAGS="${LDFLAGS}" \
    TAGS="bindata timetzdata sqlite sqlite_unlock_notify" \
    GITEA_VERSION="${VERSION}" \
        make build
)

# Binary is intentionally not renamed -- forgejo forked from gitea and
# keeps the binary name "gitea" (matches upstream's own build).
BINARY="${SRC_DIR}/gitea"
if [ ! -x "${BINARY}" ]; then
    echo "build did not produce an executable at ${BINARY}" >&2
    exit 1
fi

STAGE_DIR="${WORK_DIR}/stage"
PAYLOAD_DIR="${WORK_DIR}/payload"
mkdir -p "${STAGE_DIR}" "${PAYLOAD_DIR}/bin" "${PAYLOAD_DIR}/var"

cp "${BINARY}" "${PAYLOAD_DIR}/bin/gitea"
chmod +x "${PAYLOAD_DIR}/bin/gitea"
cp "${SCRIPT_DIR}/src/conf.ini" "${PAYLOAD_DIR}/var/conf.ini"
tar czf "${STAGE_DIR}/package.tgz" -C "${PAYLOAD_DIR}" bin var

# Generic DSM7 lifecycle scripts, shared verbatim across every package
# under packages/ (see packages/_shared/spksrc-service/NOTICE.md), plus
# this package's own service-setup.
mkdir -p "${STAGE_DIR}/scripts"
cp "${SHARED_DIR}/"* "${STAGE_DIR}/scripts/"
rm -f "${STAGE_DIR}/scripts/NOTICE.md"
cp "${SCRIPT_DIR}/src/scripts/service-setup" "${STAGE_DIR}/scripts/service-setup"
chmod +x "${STAGE_DIR}/scripts/"preinst "${STAGE_DIR}/scripts/"postinst \
    "${STAGE_DIR}/scripts/"preuninst "${STAGE_DIR}/scripts/"postuninst \
    "${STAGE_DIR}/scripts/"preupgrade "${STAGE_DIR}/scripts/"postupgrade \
    "${STAGE_DIR}/scripts/start-stop-status" "${STAGE_DIR}/scripts/installer.dsm7"

cp -R "${SCRIPT_DIR}/src/conf" "${STAGE_DIR}/conf"
cp -R "${SCRIPT_DIR}/src/wizard" "${STAGE_DIR}/wizard"

cat >"${STAGE_DIR}/INFO" <<EOF
package="forgejo"
version="${VERSION}"
arch="x86_64"
os_min_ver="${OS_MIN_VER}"
displayname="Forgejo"
description="Self-hosted lightweight Git forge, built from source at codeberg.org/forgejo/forgejo."
maintainer="synology-marketplace"
maintainer_url="https://github.com/nhymxu/spkrepo"
install_dep_packages="git>=2"
startable="yes"
EOF

mkdir -p "${OUT_DIR}"
SPK_PATH="${OUT_DIR}/forgejo-${VERSION}-x86_64.spk"
tar cf "${SPK_PATH}" -C "${STAGE_DIR}" INFO package.tgz scripts conf wizard

echo "wrote ${SPK_PATH}"
