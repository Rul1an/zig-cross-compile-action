#!/usr/bin/env bash
set -euo pipefail

# setup-env.sh
# Handles target aliasing and environment variable exports for Zig cross-compilation.
#
# This script is intended to be SOURCED by the GitHub Action in CI.
# CAUTION: Sourcing this locally will enable 'set -euo pipefail' in your current shell.

# Logging helper
if [[ "${ZIG_ACTION_DEBUG:-0}" == "1" ]]; then
    log() { echo "::debug::[zig-action] $1"; }
    # Dump initial environment states for debugging
    echo "::group::[zig-action] Debug Env Dump"
    # Grep strictly for build-related env vars to avoid accidental secret leakage
    env | grep -E '^(ZIG_|GO(OS|ARCH|FLAGS|ROOT)?=|CARGO_(TARGET|HOME|TERM|INCREMENTAL|PROFILE|ENVDIR|BUILD)=|CC=|CXX=)' || true

    # Extra context for debugging tools
    if command -v cargo >/dev/null 2>&1; then
        log "Debug: cargo version: $(cargo --version || echo 'unknown')"
    fi
    echo "::endgroup::"
else
    log() { echo "::notice::[zig-action] $1"; }
fi

# die: Fail fast.
# CAUTION: If sourced locally, this WILL exit your shell session.
die() {
    echo "::error::[zig-action] $1"
    exit 1
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

# 0. Platform & Input Checks
if [[ "${RUNNER_OS:-Linux}" == "Windows" ]]; then
    die "Windows runners are not supported as host OS. Use Ubuntu or macOS runners."
fi

# Project Type Resolution (Smart Auto)
# If 'auto', we try to detect the language to avoid conflicting policies (e.g. running Rust checks on a Go project).
if [[ "$TYPE" == "auto" ]]; then
    if [[ -f "Cargo.toml" ]]; then
        TYPE="rust"
        log "Auto-detected Rust project (found Cargo.toml). Setting project-type='rust'."
    elif [[ -f "go.mod" ]]; then
        TYPE="go"
        log "Auto-detected Go project (found go.mod). Setting project-type='go'."
    else
        TYPE="c"
        log "No Cargo.toml or go.mod found. Auto-detected project-type='c'."
    fi
fi

# Strict validation check
case "$TYPE" in
    go|rust|c|custom) ;; # valid
    *)
        # Should not be reachable given the normalization above, but safe fallback
        log "Unknown project-type '$TYPE'. Falling back to 'custom' (compiler-only)."
        log "Please set 'project-type: c/go/rust' explicitly if you need specific environment overrides."
        TYPE="custom"
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
# export_var: Writes to GITHUB_ENV (if present) AND exports to current shell.
export_var() {
    local k="$1"
    local v="$2"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        printf "%s=%s\n" "$k" "$v" >> "$GITHUB_ENV"
    fi
    export "$k=$v"
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
if [[ "$TYPE" == "go" ]]; then
    if [[ -n "$GO_OS" && -n "$GO_ARCH" ]]; then
        export_var "CGO_ENABLED" "1"
        export_var "GOOS" "$GO_OS"
        export_var "GOARCH" "$GO_ARCH"
        [[ "$TYPE" == "go" ]] && log "Go environment configured ($GO_OS/$GO_ARCH)"
    fi
fi

# C: Explicitly disable CGO to ensure pure C environment
if [[ "$TYPE" == "c" ]]; then
    export_var "CGO_ENABLED" "0"
fi

# Rust: annoying. Needs a wrapper script because cargo linker args can't handle spaces.
if [[ "$TYPE" == "rust" ]]; then
    # Check for version suffix (e.g. .2.31) which breaks env var names
    if [[ "$ZIG_TARGET" == *.* ]]; then
        log "Skipping Rust linker setup: target '$ZIG_TARGET' contains version suffix."
        log "To cross-compile Rust, use a target without glibc version (e.g. x86_64-linux-gnu)."
    else
        # Rust + Musl Policy
        if [[ "$ZIG_TARGET" == *musl* ]]; then
            # INPUT_RUST_MUSL_MODE defaults to 'deny' in action.yml
            RUST_MODE="${INPUT_RUST_MUSL_MODE:-deny}"
            case "$RUST_MODE" in
                deny)
                    die "Rust+Musl targets are disabled by default (CRT conflicts). Use a *-gnu target, use cargo-zigbuild, or set rust-musl-mode: warn/allow if you know what you're doing.
Suggested fixes:
  - target: aarch64-unknown-linux-gnu
  - or: project-type: c and use 'cargo zigbuild' instead of 'cargo build'."
                    ;;
                warn)
                    log "WARNING: Rust with Musl targets is known to be flaky due to CRT conflicts."
                    ;;
                allow)
                    log "NOTE: Rust+Musl enabled (mode: allow). Expect potential duplicate symbol errors."
                    ;;
                *)
                    log "Unknown rust-musl-mode '$RUST_MODE', treating as 'warn'."
                    ;;
            esac
        fi

        # 1. Map Zig target to Rust triple
        RUST_TRIPLE="$ZIG_TARGET"
        case "$RUST_TRIPLE" in
            *apple-darwin*|*unknown-linux-musl*|*unknown-linux-gnu*|*pc-windows-gnu*)
                ;; # Already looks like a Rust triple
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
        SANITIZED_TRIPLE=$(echo "$RUST_TRIPLE" | tr '-' '_')
        LINKER_VAR="CARGO_TARGET_$(echo "$SANITIZED_TRIPLE" | tr '[:lower:]' '[:upper:]')_LINKER"

        # 3. Create wrapper (Concurrency-safe)
        WRAPPER_DIR="${RUNNER_TEMP:-/tmp}/zig-wrappers"
        mkdir -p "$WRAPPER_DIR"

        # We use mktemp if available, otherwise fallback to simple path with PID
        if command -v mktemp >/dev/null 2>&1; then
            WRAPPER=$(mktemp "$WRAPPER_DIR/cc-$ZIG_TARGET-XXXXXX")
        else
            WRAPPER="$WRAPPER_DIR/cc-$ZIG_TARGET-$$"
        fi

        {
            echo '#!/bin/sh'
            echo "exec zig cc -target $ZIG_TARGET \"\$@\""
        } > "$WRAPPER"
        chmod +x "$WRAPPER"

        export_var "$LINKER_VAR" "$WRAPPER"
        export_var "CC_${SANITIZED_TRIPLE}" "$CC_CMD"
        export_var "CXX_${SANITIZED_TRIPLE}" "$CXX_CMD"

        # Log always to confirm it ran
        log "Rust linker configured: $LINKER_VAR=$WRAPPER (RUST_TRIPLE=$RUST_TRIPLE)"
    fi
fi

log "Environment configured successfully."

