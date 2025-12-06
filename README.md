# Zig Cross-Compiler Action

![GitHub Release](https://img.shields.io/github/v/release/Rul1an/zig-cross-compile-action?style=flat-square)
![License](https://img.shields.io/github/license/Rul1an/zig-cross-compile-action?style=flat-square)

Docker-free cross-compilation for C, C++, Rust, and Go using Zig’s `cc` / `c++` toolchain.
Turn a standard GitHub Actions runner into a cross-compiling build host — no containers, sysroots, or system headers required.

## Quick start

```yaml
# Example: Go + CGO to linux-arm64 using Zig as cross-compiler
- uses: actions/checkout@v4

- uses: actions/setup-go@v5
  with:
    go-version: '1.23'

- name: Cross-compile with Zig
  uses: Rul1an/zig-cross-compile-action@v2
  with:
    target: linux-arm64       # → aarch64-linux-musl
    project-type: go
    cmd: |
      go build -o dist/app-go-arm64 ./cmd
```

---

## What this Action does

This Action configures **Zig** as a drop-in cross-compiler:

- Installs Zig (via `goto-bus-stop/setup-zig`).
- Sets `CC`, `CXX`, `AR`, `RANLIB` to use `zig cc` / `zig c++` with the requested target.
- Configures language-specific environment:
  - Go: `CGO_ENABLED`, `GOOS`, `GOARCH`
  - Rust: `CARGO_TARGET_..._LINKER` + `CC_<TRIPLE>`, `CXX_<TRIPLE>`
- Optionally verifies output artifacts with a lightweight `file` scan.

This Action is **infrastructure**, not a helper script:

- ✅ It **does** install Zig and configure the environment for cross-compilation.
- ❌ It **does not** run `go build`, `cargo build`, `make`, or modify your project files.
- ❌ It **does not** install Go or Rust toolchains for you.

You stay in control of your build commands; the Action guarantees the compiler side is correct.

---

## Features

- **No Docker required**
  Avoids nested Docker, slow volume mounts, permission issues, and platform quirks. Runs directly on `ubuntu-latest` and `macos-latest`.

- **Opinionated environment**
  The Action **unconditionally overwrites**:
  - `CC`, `CXX`, `AR`, `RANLIB`
  - `ZIG_TARGET`
  - `CGO_ENABLED`, `GOOS`, `GOARCH` (for Go)
  - `CARGO_TARGET_<TRIPLE>_LINKER`, `CC_<TRIPLE>`, `CXX_<TRIPLE>` (for Rust)

- **Simple target aliases**
  Human-friendly targets mapped to Zig triples:
  - `linux-arm64` → `aarch64-linux-musl` (static, musl)
  - `linux-x64` → `x86_64-linux-musl`
  - `macos-arm64` → `aarch64-macos`
  - `macos-x64` → `x86_64-macos`
  - `windows-x64` → `x86_64-windows-gnu`

- **Strict Rust+Musl policy**
  Rust’s bundled Musl CRT and Zig’s Musl can conflict.
  This Action **denies Musl Rust targets by default**, with an explicit opt-out:

  ```yaml
  rust-musl-mode: deny  # default
  # or: warn / allow
  ```

- **Debug mode**
  Set `ZIG_ACTION_DEBUG: 1` to get extra logging about the configured environment.

## Inputs

| Input | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `version` | no | `0.13.0` | Zig version to install via setup-zig. |
| `target` | yes | — | Target architecture / triple or alias (e.g. `linux-arm64`). |
| `project-type` | no | `auto` | Preset: `auto`, `go`, `rust`, `c`, `custom`. |
| `rust-musl-mode` | no | `deny` | Rust+Musl policy: `deny`, `warn`, or `allow`. |
| `verify-level` | no | `basic` | Post-build verification: `basic` (file check) or `none`. |
| `cmd` | yes | — | Build command to run in the configured environment. |

### `project-type` presets

*   `auto`: Detects language based on files in the repository root:
    *   `Cargo.toml` → Rust
    *   `go.mod` → Go
    *   otherwise → C
*   `go`: Configure Go + CGO only.
*   `rust`: Configure Rust linker/wrappers only.
*   `c`: Pure C/C++: set `CC`, `CXX`, explicitly `CGO_ENABLED=0`.
*   `custom`: Only injects compiler-related env vars; no language-specific tweaks.

## Supported Runners & Targets

**Host Runners (where the Action runs):**
*   ✅ `ubuntu-latest` (Tier 1)
*   ✅ `macos-latest` (Tier 1)
*   ❌ **Windows runners are not supported as hosts** (The Action will fail fast on `RUNNER_OS == Windows`).

**Verified Target Examples:**
*   Linux (musl): `x86_64-linux-musl`, `aarch64-linux-musl`
*   Linux (glibc): `aarch64-unknown-linux-gnu`
*   Windows (target): `x86_64-windows-gnu`
*   macOS (target): `aarch64-macos`, `x86_64-macos`

*Other Zig-supported targets may work but are considered best effort.*

## Usage Examples

### 1. Go (CGO) → Linux ARM64
[View Example Code](examples/go-cgo)
```yaml
jobs:
  build-go:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'

      - name: Build Go (CGO) for linux-arm64
        uses: Rul1an/zig-cross-compile-action@v2
        with:
          target: linux-arm64           # → aarch64-linux-musl
          project-type: go
          cmd: |
            go build -o dist/app-go-arm64 ./cmd
```

### 2. Rust → aarch64-unknown-linux-gnu
[View Example Code](examples/rust-aarch64)
```yaml
jobs:
  build-rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-unknown-linux-gnu

      - name: Build Rust with Zig linker
        uses: Rul1an/zig-cross-compile-action@v2
        with:
          target: aarch64-unknown-linux-gnu
          project-type: rust
          rust-musl-mode: deny
          cmd: |
            cargo build --release --target aarch64-unknown-linux-gnu
```

### 3. C → Windows x64 (from Linux runner)
[View Example Code](examples/c-windows)
```yaml
jobs:
  build-c-win:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build C for Windows
        uses: Rul1an/zig-cross-compile-action@v2
        with:
          target: windows-x64          # → x86_64-windows-gnu
          project-type: c
          cmd: $CC src/main.c -o dist/app.exe
```

### 4. C → macOS ARM64 (from macos-latest runner)
[View Example Code](examples/c-macos)
```yaml
jobs:
  build-c-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build C for macOS ARM64
        uses: Rul1an/zig-cross-compile-action@v2
        with:
          target: aarch64-macos
          project-type: c
          cmd: $CC src/main.c -o dist/app-macos
```

## Integration Patterns

You can combine this Action with common build systems by reusing `$CC`, `$CXX`:

**CMake:**
```bash
cmake -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" .
cmake --build .
```

**Autotools:**
```bash
./configure CC="$CC" CXX="$CXX" --host="$ZIG_TARGET"
make
```

**Make:**
```bash
make CC="$CC" CXX="$CXX"
```

## Monorepos

`project-type: auto` only inspects the current working directory (typically repo root):

If your Go/Rust project lives in a subdirectory (e.g. `services/api`), either:
1.  Set `project-type` explicitly (`go` / `rust` / `c`), or
2.  Adjust your workflow `working-directory` and `cmd` accordingly.

**Example:**
```yaml
defaults:
  run:
    working-directory: services/rust-api

steps:
  - uses: actions/checkout@v4
  - uses: dtolnay/rust-toolchain@stable
  - uses: Rul1an/zig-cross-compile-action@v2
    with:
      target: aarch64-unknown-linux-gnu
      project-type: rust
      cmd: cargo build --release --target aarch64-unknown-linux-gnu
```

## Optional: Zig Caching

The Action itself is cache-agnostic, but you can speed up CI by caching Zig’s local data:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/zig
    key: zig-${{ inputs.version }}-${{ runner.os }}-${{ runner.arch }}
    restore-keys: |
      zig-${{ inputs.version }}-${{ runner.os }}-
      zig-${{ inputs.version }}-
```

## Debugging

Set `ZIG_ACTION_DEBUG: 1` to enable verbose logging:
*   Initial relevant environment (`ZIG_*`, `GO*`, `CARGO_*`, `CC`, `CXX`).
*   Resolved `ZIG_TARGET`.
*   Rust triple + configured `CARGO_TARGET_*_LINKER` (when applicable).

This makes it easier to diagnose misconfigured targets or unexpected toolchain behavior.

---

If you want deterministic, Docker-free cross-compilation with minimal configuration, this Action gives you a clean, opinionated foundation for your CI pipelines.
