#!/bin/bash
set -euo pipefail

# setup-env.sh
# Handles target aliasing and environment variable exports for Zig cross-compilation.
#
# This script is intended to be SOURCED by the GitHub Action.
# If run directly by a developer, it will exit the shell unless guarded.

log() { echo "::notice::[zig-action] $1"; }
die() { echo "::error::[zig-action] $1"; exit 1; }

# Guard against direct execution if sourced usage is expected, though for Github Actions
# simply exiting is fine. For local dev usage, we return instead of exit if sourced.
is_sourced() {
    if [ -n "${BASH_SOURCE-}" ] && [ "${BASH_SOURCE[0]}" != "${0}" ]; then
        return 0
    fi
    return 1
}

# Safely handle exit/return based on execution mode
safe_exit() {
    if is_sourced; then
        return "$1"
    else
        exit "$1"
    fi
}

TARGET="${INPUT_TARGET:-${1:-}}"
TYPE="${INPUT_PROJECT_TYPE:-auto}"

if [[ -z "$TARGET" ]]; then
    die "Target is required. (inputs.target)"
    safe_exit 1
fi

# Security: Sanitize target input
if [[ ! "$TARGET" =~ ^[a-zA-Z0-9_\.-]+$ ]]; then
    die "Invalid characters in target string: '$TARGET'"
    safe_exit 1
fi

# 1. Alias Resolution
# We map convenience aliases to "safe defaults" (static musl, etc).
# Note: MacOS bash is ancient (v3.2), so no associative arrays. Using simple case.
case "$TARGET" in
    "linux-arm64"|"linux-aarch64") ZIG_TARGET="aarch64-linux-musl" ;;
    "linux-x64"|"linux-amd64")     ZIG_TARGET="x86_64-linux-musl" ;;
    "macos-arm64"|"darwin-arm64")  ZIG_TARGET="aarch64-macos" ;;
    "macos-x64"|"darwin-amd64")    ZIG_TARGET="x86_64-macos" ;;
    "windows-x64"|"windows-amd64") ZIG_TARGET="x86_64-windows-gnu" ;;
    *)                             ZIG_TARGET="$TARGET" ;;
esac

# Initialize heuristic vars to empty to satisfy set -u
GO_OS=""
GO_ARCH=""

# Heuristic: Detect OS/Arch for other tools if not explicitly set
if [[ "$ZIG_TARGET" == *linux* ]]; then
    GO_OS="linux"
    [[ "$ZIG_TARGET" == *aarch64* ]] && GO_ARCH="arm64"
    [[ "$ZIG_TARGET" == *x86_64* ]] && GO_ARCH="amd64"
elif [[ "$ZIG_TARGET" == *macos* ]]; then
    GO_OS="darwin"
    [[ "$ZIG_TARGET" == *aarch64* ]] && GO_ARCH="arm64"
    [[ "$ZIG_TARGET" == *x86_64* ]] && GO_ARCH="amd64"
elif [[ "$ZIG_TARGET" == *windows* ]]; then
    GO_OS="windows"
    [[ "$ZIG_TARGET" == *x86_64* ]] && GO_ARCH="amd64"
fi

# 2. Export Helper
# Github Actions uses $GITHUB_ENV; local shell uses export.
export_var() {
    local k="$1"
    local v="$2"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        printf "%s=%s\n" "$k" "$v" >> "$GITHUB_ENV"
    else
        export "$k=$v"
    fi
}

# 3. Compiler Definitions
# Zig cc acts as a drop-in C compiler.
CC_CMD="zig cc -target $ZIG_TARGET"
CXX_CMD="zig c++ -target $ZIG_TARGET"

export_var "CC" "$CC_CMD"
export_var "CXX" "$CXX_CMD"
export_var "AR" "zig ar"
export_var "RANLIB" "zig ranlib"
export_var "ZIG_TARGET" "$ZIG_TARGET"

log "Target resolved: $ZIG_TARGET"

# 4. Project-Specific Configs

# Go: trivial, just set the vars if we know the OS/ARCH
if [[ "$TYPE" == "go" || "$TYPE" == "auto" ]]; then
    if [[ -n "$GO_OS" && -n "$GO_ARCH" ]]; then
        export_var "CGO_ENABLED" "1"
        export_var "GOOS" "$GO_OS"
        export_var "GOARCH" "$GO_ARCH"
        [[ "$TYPE" == "go" ]] && log "Go environment configured ($GO_OS/$GO_ARCH)"
    fi
fi

# Rust: annoying. Needs a wrapper script because cargo linker args can't handle spaces.
if [[ "$TYPE" == "rust" || "$TYPE" == "auto" ]]; then
    # Rust target triple guess (often matches Zig target, but not always)
    RUST_TRIPLE="${ZIG_TARGET/macos/apple-darwin}"
    RUST_TRIPLE="${RUST_TRIPLE/linux-musl/unknown-linux-musl}"
    RUST_TRIPLE="${RUST_TRIPLE/linux-gnu/unknown-linux-gnu}"
    RUST_TRIPLE="${RUST_TRIPLE/windows-gnu/pc-windows-gnu}"

    # Env var format: CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER
    # replacing underscores can be tricky if the triple has them, but triples usually use hyphens.
    SANITIZED_TRIPLE=$(echo "$RUST_TRIPLE" | tr '-' '_')
    LINKER_VAR="CARGO_TARGET_$(echo "$SANITIZED_TRIPLE" | tr '[:lower:]' '[:upper:]')_LINKER"

    # Create the wrapper
    WRAPPER_DIR="${RUNNER_TEMP:-/tmp}/zig-wrappers"
    mkdir -p "$WRAPPER_DIR"
    WRAPPER="$WRAPPER_DIR/cc-$ZIG_TARGET"

    # We use $@ to pass through all args from cargo to zig cc
    echo '#!/bin/sh' > "$WRAPPER"
    echo "exec zig cc -target $ZIG_TARGET \"\$@\"" >> "$WRAPPER"
    chmod +x "$WRAPPER"

    export_var "$LINKER_VAR" "$WRAPPER"

    # Set CC/CXX for the 'cc' crate (used by many sys crates)
    export_var "CC_${SANITIZED_TRIPLE}" "$CC_CMD"
    export_var "CXX_${SANITIZED_TRIPLE}" "$CXX_CMD"

    [[ "$TYPE" == "rust" ]] && log "Rust linker configured ($LINKER_VAR)"
fi

log "Environment configured successfully."
safe_exit 0

