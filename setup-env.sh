#!/bin/bash
set -euo pipefail

# setup-env.sh
# Handles target aliasing and environment variable exports for Zig cross-compilation.
#
# This script is intended to be SOURCED by the GitHub Action in CI.
# CAUTION: Sourcing this locally will enable 'set -euo pipefail' in your current shell.

log() { echo "::notice::[zig-action] $1"; }
# die uses safe_exit to respect sourced execution
die() { echo "::error::[zig-action] $1"; safe_exit 1; }

# Guard against direct execution if sourced usage is expected, though for Github Actions
# simply exiting is fine.
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
# Normalize TYPE to lowercase to avoid case-sensitivity issues
TYPE=$(printf '%s' "${TYPE}" | tr '[:upper:]' '[:lower:]')

if [[ -z "$TARGET" ]]; then
    die "Target is required. (inputs.target)"
fi

# Security: Sanitize target input
if [[ ! "$TARGET" =~ ^[a-zA-Z0-9_\.-]+$ ]]; then
    die "Invalid characters in target string: '$TARGET'"
fi

# Normalize known Rust-style target triples to Zig-style OS names
# so we can accept either Zig or Rust triples as input.
case "$TARGET" in
    *unknown-linux-musl)
        TARGET="${TARGET/unknown-linux-musl/linux-musl}"
        ;;
    *unknown-linux-gnu)
        TARGET="${TARGET/unknown-linux-gnu/linux-gnu}"
        ;;
    *apple-darwin)
        TARGET="${TARGET/apple-darwin/macos}"
        ;;
    *pc-windows-gnu)
        TARGET="${TARGET/pc-windows-gnu/windows-gnu}"
        ;;
esac

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
    # Check for version suffix (e.g. .2.31) which breaks env var names
    if [[ "$ZIG_TARGET" == *.* ]]; then
        log "Skipping Rust linker setup: target '$ZIG_TARGET' contains version suffix."
        log "To cross-compile Rust, use a target without glibc version (e.g. x86_64-linux-gnu)."
    elif [[ "$ZIG_TARGET" == *musl* ]]; then
        log "WARNING: Rust with Musl targets is known to be flaky due to CRT conflicts (duplicate symbols)."
        log "If the build fails, try switching to a glibc target (*-gnu) or set 'project-type: c' and use 'cargo-zigbuild'."
        # We proceed anyway, but user is warned.

        # 1. Map Zig target to Rust triple
        RUST_TRIPLE="$ZIG_TARGET"
        case "$RUST_TRIPLE" in
            *apple-darwin*|*unknown-linux-musl*|*unknown-linux-gnu*|*pc-windows-gnu*)
                ;; # Already valid Rust triple
            *macos*)
                RUST_TRIPLE="${RUST_TRIPLE/macos/apple-darwin}"
                ;;
            *linux-musl*)
                RUST_TRIPLE="${RUST_TRIPLE/linux-musl/unknown-linux-musl}"
                ;;
            *linux-gnu*)
                RUST_TRIPLE="${RUST_TRIPLE/linux-gnu/unknown-linux-gnu}"
                ;;
            *windows-gnu*)
                RUST_TRIPLE="${RUST_TRIPLE/windows-gnu/pc-windows-gnu}"
                ;;
        esac

        # 2. Variable sanitization
        # CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER
        SANITIZED_TRIPLE=$(echo "$RUST_TRIPLE" | tr '-' '_')
        LINKER_VAR="CARGO_TARGET_$(echo "$SANITIZED_TRIPLE" | tr '[:lower:]' '[:upper:]')_LINKER"

        # Create wrapper
        WRAPPER_DIR="${RUNNER_TEMP:-/tmp}/zig-wrappers"
        mkdir -p "$WRAPPER_DIR"
        WRAPPER="$WRAPPER_DIR/cc-$ZIG_TARGET"

        echo '#!/bin/sh' > "$WRAPPER"
        echo "exec zig cc -target $ZIG_TARGET \"\$@\"" >> "$WRAPPER"
        chmod +x "$WRAPPER"

        export_var "$LINKER_VAR" "$WRAPPER"

        # Set CC/CXX for the 'cc' crate
        export_var "CC_${SANITIZED_TRIPLE}" "$CC_CMD"
        export_var "CXX_${SANITIZED_TRIPLE}" "$CXX_CMD"

        [[ "$TYPE" == "rust" ]] && log "Rust linker configured ($LINKER_VAR)"
    fi
fi

log "Environment configured successfully."
safe_exit 0
