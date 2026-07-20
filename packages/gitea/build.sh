#!/usr/bin/env bash
# Build a DSM7 x86_64 .spk for Gitea (https://github.com/go-gitea/gitea)
# from source, following the same build recipe as the real, maintained
# SynoCommunity/spksrc gitea package (cross/gitea/Makefile,
# spk/gitea/Makefile): fetch Gitea's own release source archive, build
# with CGO/sqlite/bindata, embed config paths via ldflags, and package
# with the git dependency + dedicated-user + shared-folder wizard the
# real package uses.
#
# Run on an x86_64 Linux host with Go >= 1.26, Node >= 22, `make`, gcc
# (CGO_ENABLED=1) -- no cross-compilation. Gitea's frontend build is
# pinned to a specific pnpm version via its own package.json
# "packageManager" field; run `corepack enable` once before this script
# so pnpm resolves and installs that pinned version automatically.
#
# Usage:
#   packages/gitea/build.sh --version 1.26.2 [--rev N] [--os-min-ver 7.0-40000] [--out DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../_shared/spksrc-service"
# shellcheck source=../_shared/spk-package.sh
source "${SCRIPT_DIR}/../_shared/spk-package.sh"

spk_parse_build_args "$@"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
STAGE_DIR="${WORK_DIR}/stage"
PAYLOAD_DIR="${WORK_DIR}/payload"

SRC_DIR="${WORK_DIR}/gitea-${VERSION}"
TARBALL="${WORK_DIR}/gitea-${VERSION}.tar.gz"
TARBALL_URL="https://github.com/go-gitea/gitea/archive/v${VERSION}.tar.gz"

echo "fetching ${TARBALL_URL} ..." >&2
curl -fsSL "${TARBALL_URL}" -o "${TARBALL}"
mkdir -p "${SRC_DIR}"
tar xzf "${TARBALL}" -C "${SRC_DIR}" --strip-components=1

# Persistent runtime paths, baked into the binary at build time (matches
# cross/gitea/Makefile) so Gitea has sane defaults even without the env
# vars start-stop-status also sets.
PKG_VAR="/var/packages/gitea/var"
LDFLAGS="-X \"code.gitea.io/gitea/modules/setting.CustomPath=${PKG_VAR}/custom\""
LDFLAGS="${LDFLAGS} -X \"code.gitea.io/gitea/modules/setting.CustomConf=${PKG_VAR}/conf.ini\""
LDFLAGS="${LDFLAGS} -X \"code.gitea.io/gitea/modules/setting.AppWorkPath=${PKG_VAR}\""
LDFLAGS="${LDFLAGS} -X \"code.gitea.io/gitea/modules/setting.PIDFile=${PKG_VAR}/gitea.pid\""

echo "building (make build, TAGS=bindata sqlite sqlite_unlock_notify) ..." >&2
(
    cd "${SRC_DIR}"
    CGO_ENABLED=1 \
    EXTRA_GOFLAGS=-buildvcs=false \
    LDFLAGS="${LDFLAGS}" \
    TAGS="bindata sqlite sqlite_unlock_notify" \
    GITEA_VERSION="${VERSION}" \
        make build
)

# Gitea's own Makefile already defaults EXECUTABLE to "gitea" -- no
# rename needed (unlike forgejo, which forked from gitea but keeps that
# same binary name for a different reason).
BINARY="${SRC_DIR}/gitea"
if [ ! -x "${BINARY}" ]; then
    echo "build did not produce an executable at ${BINARY}" >&2
    exit 1
fi

spk_stage_package "${BINARY}" "gitea"

cat >"${STAGE_DIR}/INFO" <<EOF
package="gitea"
version="${PKG_VERSION}"
arch="x86_64"
os_min_ver="${OS_MIN_VER}"
displayname="Gitea"
description="Community managed, self-hosted lightweight Git service, built from source at github.com/go-gitea/gitea."
maintainer="Dung Nguyen (nhymxu)"
maintainer_url="https://github.com/nhymxu/spkrepo"
install_dep_packages="git>=2"
startable="yes"
EOF

spk_append_icons

spk_write_archive "gitea"
