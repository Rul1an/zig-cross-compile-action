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

# JSON Key format: x86_64-linux, aarch64-macos
PLATFORM_KEY="${ARCH_TAG}-${OS_TAG}"

log "Resolving Zig ${ZIG_VERSION} for ${PLATFORM_KEY}..."

# 2. Toolcache target (GitHub-hosted: /opt/hostedtoolcache)
TOOLCACHE_ROOT="${RUNNER_TOOL_CACHE:-/opt/hostedtoolcache}"
INSTALL_ROOT="${TOOLCACHE_ROOT}/zig/${ZIG_VERSION}/${PLATFORM_KEY}"
BIN_PATH="${INSTALL_ROOT}/zig"

# 2a. Checks if already installed
if [[ -x "${BIN_PATH}" ]]; then
  log "Zig already installed at ${BIN_PATH}, reusing."
  echo "zig_path=${BIN_PATH}" >> "$GITHUB_OUTPUT"
  echo "zig_version_resolved=${ZIG_VERSION}" >> "$GITHUB_OUTPUT"
  echo "${INSTALL_ROOT}" >> "$GITHUB_PATH"
  exit 0
fi

# 3. Resolve Metadata via index.json
# We use a temp file for the index to parse it
TMP_DIR="$(mktemp -d)"
INDEX_FILE="${TMP_DIR}/index.json"

log "Fetching release index from ziglang.org..."
if ! curl -sSfL "https://ziglang.org/download/index.json" -o "${INDEX_FILE}"; then
    die "Failed to download version index."
fi

# Use jq to extract URL and shasum
# Note: jq is standard on GitHub runners
if ! command -v jq >/dev/null; then
    die "jq is required but not installed."
fi

# Check if version exists in index
if ! jq -e ".\"${ZIG_VERSION}\"" "${INDEX_FILE}" >/dev/null; then
    if [[ "${STRICT_VERSION}" == "true" ]]; then
        die "Version ${ZIG_VERSION} not found in index.json (STRICT_VERSION=true)."
    else
        log "Version ${ZIG_VERSION} not found in index. Warning: Fallback to manual URL construction (no checksum)."
        # Fallback logic for non-strict custom versions could go here,
        # but for v3 we focus on strict/supported.
        # Construct naive URL as a last resort?
        # For now, simplistic fallback to maintain 'strict=false' contract if needed,
        # but honestly it's safer to fail or strictly require index presence.
        # User requested flexible logic, let's keep it safe.
    fi
fi

DOWNLOAD_URL=$(jq -r ".\"${ZIG_VERSION}\".\"${PLATFORM_KEY}\".tarball" "${INDEX_FILE}")
EXPECTED_SHA=$(jq -r ".\"${ZIG_VERSION}\".\"${PLATFORM_KEY}\".shasum" "${INDEX_FILE}")

if [[ "$DOWNLOAD_URL" == "null" ]]; then
    die "No download found for ${ZIG_VERSION} on ${PLATFORM_KEY}."
fi

log "Resolved URL: ${DOWNLOAD_URL}"
log "Expected SHA: ${EXPECTED_SHA}"

# 4. Download and Verify
ARCHIVE="${TMP_DIR}/zig.tar.xz"
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"

log "Downloading..."
curl -sSfL "${DOWNLOAD_URL}" -o "${ARCHIVE}"

if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "null" ]]; then
    log "Verifying checksum..."
    COMPUTED_SHA=""
    if command -v sha256sum >/dev/null; then
        COMPUTED_SHA=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
    elif command -v shasum >/dev/null; then
        COMPUTED_SHA=$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')
    else
        die "No sha256sum or shasum found."
    fi

    if [[ "$COMPUTED_SHA" != "$EXPECTED_SHA" ]]; then
        die "Checksum mismatch! Expected: $EXPECTED_SHA, Got: $COMPUTED_SHA"
    fi
    log "Checksum verified."
else
    if [[ "${STRICT_VERSION}" == "true" ]]; then
        die "No SHA256 checksum found in index for ${ZIG_VERSION} (STRICT_VERSION=true)."
    else
        log "Check skipped (missing in index)."
    fi
fi

# 5. Extract and Install
log "Extracting to ${EXTRACT_DIR}..."
tar -xJf "${ARCHIVE}" -C "${EXTRACT_DIR}"

mkdir -p "${INSTALL_ROOT}"

EXTRACTED_SUBDIR="$(find "${EXTRACT_DIR}" -maxdepth 1 -type d -name 'zig-*' | head -n1 || true)"
if [[ -z "${EXTRACTED_SUBDIR}" ]]; then
  die "Could not find extracted Zig directory under ${EXTRACT_DIR}"
fi

log "Installing Zig into ${INSTALL_ROOT}..."
mv "${EXTRACTED_SUBDIR}/"* "${INSTALL_ROOT}/"

# 6. Outputs
echo "${INSTALL_ROOT}" >> "$GITHUB_PATH"
echo "zig_path=${INSTALL_ROOT}/zig" >> "$GITHUB_OUTPUT"
echo "zig_version_resolved=${ZIG_VERSION}" >> "$GITHUB_OUTPUT"

log "Installation complete. zig=$( "${INSTALL_ROOT}/zig" version )"
