#!/usr/bin/env bash
set -euo pipefail

log() { echo "::notice::[install-zig] $1"; }
die() { echo "::error::[install-zig] $1"; exit 1; }

ZIG_VERSION="${ZIG_VERSION:-0.13.0}"
STRICT_VERSION="${STRICT_VERSION:-true}"

# 1. OS/arch detectie
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  OS_TAG="linux" ;;
  Darwin) OS_TAG="macos" ;;
  *)      die "Unsupported OS: $OS" ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_TAG="x86_64" ;;
  arm64|aarch64) ARCH_TAG="aarch64" ;;
  *)            die "Unsupported ARCH: $ARCH" ;;
esac

log "Resolving Zig ${ZIG_VERSION} for ${ARCH_TAG}-${OS_TAG}..."

# 2. Toolcache target (GitHub-hosted: /opt/hostedtoolcache)
TOOLCACHE_ROOT="${RUNNER_TOOL_CACHE:-/opt/hostedtoolcache}"
INSTALL_ROOT="${TOOLCACHE_ROOT}/zig/${ZIG_VERSION}/${ARCH_TAG}-${OS_TAG}"
BIN_PATH="${INSTALL_ROOT}/zig"

# 2a. Als hij al bestaat, alleen exporten en klaar
if [[ -x "${BIN_PATH}" ]]; then
  log "Zig already installed at ${BIN_PATH}, reusing."
  echo "zig_path=${BIN_PATH}" >> "$GITHUB_OUTPUT"
  echo "zig_version_resolved=${ZIG_VERSION}" >> "$GITHUB_OUTPUT"
  echo "${INSTALL_ROOT}" >> "$GITHUB_PATH"
  exit 0
fi

# 3. Download & extract in temp dir
# Explicitly use -t to avoid platform differences in mktemp if possible,
# but simply mktemp -d is often enough. User suggested -t zig-install-XXXXXX.
TMP_DIR="$(mktemp -d)"
ARCHIVE="${TMP_DIR}/zig.tar.xz"
EXTRACT_DIR="${TMP_DIR}/extracted"

mkdir -p "${EXTRACT_DIR}"

# Zig officiële tarball naamgeving
case "${OS_TAG}" in
  linux)  TARBALL="zig-linux-${ARCH_TAG}-${ZIG_VERSION}.tar.xz" ;;
  macos)  TARBALL="zig-macos-${ARCH_TAG}-${ZIG_VERSION}.tar.xz" ;;
esac

BASE_URL="https://ziglang.org/download/${ZIG_VERSION}"
URL="${BASE_URL}/${TARBALL}"
SHA_URL="${URL}.sha256"

log "Downloading ${URL}..."
curl -sSfL "${URL}" -o "${ARCHIVE}"

# 4. Optionele checksum check (strong default)
log "Verifying checksum..."
if curl -sSfL "${SHA_URL}" -o "${ARCHIVE}.sha256"; then
  # checksum check
  (
    cd "${TMP_DIR}"
    if command -v sha256sum >/dev/null; then
        sha256sum -c "$(basename "${ARCHIVE}.sha256")"
    elif command -v shasum >/dev/null; then
        shasum -a 256 -c "$(basename "${ARCHIVE}.sha256")"
    else
        die "No sha256sum or shasum found."
    fi
  ) || die "Checksum verification failed."
  log "Checksum ok."
else
  if [[ "${STRICT_VERSION}" == "true" ]]; then
    die "Checksum file not found for ${ZIG_VERSION} (STRICT_VERSION=true)."
  else
    log "No checksum file found; continuing without verification (STRICT_VERSION=false)."
  fi
fi

log "Extracting to temporary dir ${EXTRACT_DIR}..."
tar -xJf "${ARCHIVE}" -C "${EXTRACT_DIR}"

# 5. Verplaats naar toolcache
mkdir -p "${INSTALL_ROOT}"

# Extracted dir heet meestal 'zig-linux-x86_64-0.13.0'
EXTRACTED_SUBDIR="$(find "${EXTRACT_DIR}" -maxdepth 1 -type d -name 'zig-*' | head -n1 || true)"
if [[ -z "${EXTRACTED_SUBDIR}" ]]; then
  die "Could not find extracted Zig directory under ${EXTRACT_DIR}"
fi

log "Installing Zig into ${INSTALL_ROOT}..."
mv "${EXTRACTED_SUBDIR}/"* "${INSTALL_ROOT}/"

# 6. PATH en outputs
echo "${INSTALL_ROOT}" >> "$GITHUB_PATH"
echo "zig_path=${INSTALL_ROOT}/zig" >> "$GITHUB_OUTPUT"
echo "zig_version_resolved=${ZIG_VERSION}" >> "$GITHUB_OUTPUT"

log "Installation complete. zig=$( "${INSTALL_ROOT}/zig" version )"
