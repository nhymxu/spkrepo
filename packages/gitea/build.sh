#!/usr/bin/env bash
# Build a DSM7 x86_64 .spk for Gitea (https://github.com/go-gitea/gitea)
# from source, following the same build recipe as the real, maintained
# SynoCommunity/spksrc gitea package (cross/gitea/Makefile,
# spk/gitea/Makefile): fetch Gitea's own release source archive, build
# with CGO/sqlite/bindata, embed config paths via ldflags, and package
# with the git dependency + dedicated-user + shared-folder wizard the
# real package uses.
#
# Run on an x86_64 Linux host with Go >= 1.26, Node >= 24, `make`, gcc
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
# cross/gitea/Makefile). These are the *only* thing pointing Gitea at the
# pre-seeded conf.ini -- service-setup passes neither --config nor
# GITEA_WORK_DIR/GITEA_CUSTOM.
#
# The module path is read from go.mod instead of hardcoded: Gitea renamed its
# module from "code.gitea.io/gitea" to "gitea.dev" in 1.27, and the Go linker
# silently ignores a -X naming a symbol it can't resolve. A stale hardcoded
# path would not fail the build -- it would produce a binary that quietly
# falls back to <bindir>/custom/conf/app.ini and re-runs the web installer.
GO_MODULE="$(awk '$1 == "module" { print $2; exit }' "${SRC_DIR}/go.mod")"
if [ -z "${GO_MODULE}" ]; then
    echo "could not read module path from ${SRC_DIR}/go.mod" >&2
    exit 1
fi

PKG_VAR="/var/packages/gitea/var"

# symbol=value pairs. Note PIDFile is declared in package cmd (cmd/web.go),
# not modules/setting -- spksrc's Makefile targets setting.PIDFile, which
# resolves to nothing. Harmless there (service-setup passes --pid explicitly),
# but name the symbol that actually exists.
LDFLAG_SYMBOLS=(
    "${GO_MODULE}/modules/setting.CustomPath=${PKG_VAR}/custom"
    "${GO_MODULE}/modules/setting.CustomConf=${PKG_VAR}/conf.ini"
    "${GO_MODULE}/modules/setting.AppWorkPath=${PKG_VAR}"
    "${GO_MODULE}/cmd.PIDFile=${PKG_VAR}/gitea.pid"
)

LDFLAGS=""
for ldflag_symbol in "${LDFLAG_SYMBOLS[@]}"; do
    LDFLAGS="${LDFLAGS}${LDFLAGS:+ }-X \"${ldflag_symbol}\""
done

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

# Deriving the module path from go.mod covers a rename of the module itself,
# but a -X is dropped just as silently if the *variable* moves or is renamed.
# Grepping the binary for the injected paths can't detect that -- the linker
# writes the -X payload into the binary whether or not the symbol resolved --
# so check the symbol table, which only lists targets that really exist.
NM_OUTPUT="${WORK_DIR}/symbols.txt"
go tool nm "${BINARY}" >"${NM_OUTPUT}"
for ldflag_symbol in "${LDFLAG_SYMBOLS[@]}"; do
    symbol="${ldflag_symbol%%=*}"
    # Exact match on the symbol field -- a substring test would accept
    # "...CustomConfRenamed" as proof that "...CustomConf" still exists.
    if ! awk -v sym="${symbol}" '$NF == sym { found = 1; exit } END { exit !found }' "${NM_OUTPUT}"; then
        echo "ldflag target ${symbol} is not in the built binary's symbol table," >&2
        echo "so the linker silently ignored it and the package would ignore its" >&2
        echo "own conf.ini. Upstream moved or renamed it -- update LDFLAG_SYMBOLS." >&2
        exit 1
    fi
done

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
