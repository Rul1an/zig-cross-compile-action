# Architecture: Zig Cross-Compiler GitHub Action

This document describes the architecture, behavior, and trade-offs of the `zig-cross-compile-action`.

- **Role:** Toolchain injector (configures a cross-compiler)
- **Philosophy:** Infrastructure, not helper
- **Primary tools:** `zig cc`, `zig c++`

---

## 1. Scope and Design Goals

### 1.1 In Scope

- Configure **Zig** as a cross-compiler for:
  - C / C++
  - Go (with CGO)
  - Rust (via Zig as linker)
- Map **human-friendly targets** to Zig targets (e.g. `linux-arm64` → `aarch64-linux-musl`).
- Export compiler-related environment variables into the job:
  - `CC`, `CXX`, `AR`, `RANLIB`, `ZIG_TARGET`
  - Go: `CGO_ENABLED`, `GOOS`, `GOARCH`
  - Rust: `CARGO_TARGET_<TRIPLE>_LINKER`, `CC_<TRIPLE>`, `CXX_<TRIPLE>`

### 1.2 Out of Scope / Non-Goals

- Running build tools (`go build`, `cargo build`, `make`, `cmake`, etc.).
- Installing Go or Rust toolchains.
- Modifying project files (`Cargo.toml`, `go.mod`, `.cargo/config`).
- Supporting Windows **as a host**. Windows is supported as a *target* only.

### 1.3 Host & Target Support

- **Supported hosts (runners):**
  - `ubuntu-latest`
  - `macos-latest`
- **Host not supported:**
  - `windows-*` → the action fails fast if `RUNNER_OS == "Windows"`.

- **Verified targets (examples, not exhaustive):**
  - Linux (musl): `x86_64-linux-musl`, `aarch64-linux-musl`
  - Linux (glibc): `aarch64-unknown-linux-gnu`
  - Windows: `x86_64-windows-gnu`
  - macOS: `aarch64-macos`, `x86_64-macos`

Other Zig targets may work but are treated as best-effort.

---

## 2. High-Level Architecture

The action consists of:

1. **`action.yml`** – Composite action interface and steps.
2. **`setup-env.sh`** – Environment controller:
   - Normalizes targets.
   - Resolves `project-type`.
   - Exports environment variables.
   - Configures Rust linker wrappers.

### 2.1 `action.yml` Overview

Key inputs:

- `version`: Zig toolchain version (default `0.13.0`).
- `target`: Requested architecture / triple or alias (required).
- `project-type`: Language preset (`auto`, `go`, `rust`, `c`, `custom`).
- `rust-musl-mode`: Policy for Rust + Musl (`deny`, `warn`, `allow`).
- `verify-level`: Post-build check (`basic` or `none`).
- `cmd`: Build command to execute (required).

Execution flow (per job):

1. **Setup environment**
   Calls `setup-env.sh` via `source`, passing `INPUT_*` env vars.
2. **Install Zig**
   Uses `goto-bus-stop/setup-zig` with the requested version.
3. **Run build command**
   Executes `cmd` in a shell, with the configured environment.
4. **Optional verification**
   If `verify-level != none` and not on Windows, run a heuristic `file` scan to detect binaries (ELF / Mach-O / PE).

---

## 3. Environment Controller (`setup-env.sh`)

### 3.1 Shell & Logging

- Script runs with `set -euo pipefail` for strict error handling.
- Logging via GitHub Actions annotations:
  - Default: `::notice::[zig-action] ...`
  - With `ZIG_ACTION_DEBUG=1`: `::debug::[zig-action] ...` plus a small debug env dump.

### 3.2 Input Validation & Normalization

- `TARGET`:
  - Must match regex `^[a-zA-Z0-9_\.-]+$`.
    Otherwise the script fails immediately.
  - Rust-style triples are normalized to Zig-style OS names:
    - `*unknown-linux-musl` → `*linux-musl`
    - `*unknown-linux-gnu` → `*linux-gnu`
    - `*apple-darwin` → `*macos`
    - `*pc-windows-gnu` → `*windows-gnu`
- Host check:
  - If `RUNNER_OS == "Windows"` → hard fail with explanation.

### 3.3 Project Type Resolution

`project-type` controls which language-specific behavior is enabled.

- If `project-type == auto`:
  - If `Cargo.toml` in current directory → `rust`.
  - Else if `go.mod` in current directory → `go`.
  - Else → `c`.
- If `project-type` is anything else, it must be one of:
  - `go`, `rust`, `c`, `custom`.
  Unknown values fall back to `custom` with a warning.

**Monorepos:**
Auto detection is **root-only**. Subdirectories are not scanned. In monorepos, callers should either:

- Set `project-type` explicitly, or
- Adjust `working-directory` in the workflow.

### 3.4 Target Alias Resolution

Aliases are mapped to safer default Zig targets:

- `linux-arm64`, `linux-aarch64` → `aarch64-linux-musl`
- `linux-x64`, `linux-amd64` → `x86_64-linux-musl`
- `macos-arm64`, `darwin-arm64` → `aarch64-macos`
- `macos-x64`, `darwin-amd64` → `x86_64-macos`
- `windows-x64`, `windows-amd64` → `x86_64-windows-gnu`

Any other value is used as-is as `ZIG_TARGET`.

The script also derives `GOOS` / `GOARCH` heuristically from `ZIG_TARGET` (linux/macos/windows + `aarch64`/`x86_64`).

### 3.5 Env Export Mechanism

A helper `export_var` abstracts writing variables:

- In GitHub Actions:
  - Writes `KEY=VALUE` to `$GITHUB_ENV`.
- Locally:
  - Calls `export KEY=VALUE`.

Core exports (always set):

- `CC="zig cc -target $ZIG_TARGET"`
- `CXX="zig c++ -target $ZIG_TARGET"`
- `AR="zig ar"`
- `RANLIB="zig ranlib"`
- `ZIG_TARGET="$ZIG_TARGET"`

---

## 4. Language-Specific Behavior

### 4.1 Go / CGO

**Condition:** `project-type == go`

- Requires Go toolchain to be pre-installed (e.g. via `actions/setup-go`).
- If `GO_OS` and `GO_ARCH` were derived from `ZIG_TARGET`, the script exports:
  - `CGO_ENABLED=1`
  - `GOOS=$GO_OS`
  - `GOARCH=$GO_ARCH`
- Logs a notice indicating the effective Go target.

For **pure Go** builds (no CGO), users should:

- Use `project-type: custom`, or
- Manually set `CGO_ENABLED=0` in their workflow.

### 4.2 C / C++

**Condition:** `project-type == c`

- Only configures the compiler:
  - `CC`, `CXX`, `AR`, `RANLIB`, `ZIG_TARGET` (as above).
- Additionally:
  - `CGO_ENABLED=0` is set explicitly to prevent cross-talk with Go in mixed repos.

Typical usage with build systems:

- CMake: `-DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"`
- Autotools: `./configure CC="$CC" CXX="$CXX" --host="$ZIG_TARGET"`
- Make: `make CC="$CC" CXX="$CXX"`

### 4.3 Rust

**Condition:** `project-type == rust`

#### 4.3.1 Musl Policy

Zig ships its own Musl libc, and Rust’s Musl targets also ship a self-contained CRT. Using both can cause duplicate symbol errors (`_start`, `_init`, etc.).

- `rust-musl-mode` input controls behavior for `*musl` targets:
  - `deny` (default): fail with an explicit error and suggested alternatives.
  - `warn`: log a warning, continue.
  - `allow`: log a note and continue (no extra safety checks).

If `ZIG_TARGET` contains a version suffix (e.g. `x86_64-linux-gnu.2.31`), Rust setup is skipped to avoid invalid env var names.

#### 4.3.2 Triple Mapping & Linker Wrapper

To configure Cargo’s linker:

1. **Zig → Rust triple mapping**

   - If `ZIG_TARGET` is already a Rust triple (`*unknown-linux-*`, `*apple-darwin*`, `*pc-windows-gnu*`), it is left unchanged.
   - Otherwise, OS components are rewritten:
     - `*macos` → `*apple-darwin`
     - `*linux-musl` → `*unknown-linux-musl`
     - `*linux-gnu` → `*unknown-linux-gnu`
     - `*windows-gnu` → `*pc-windows-gnu`

2. **Env var names**

   - Rust triple is sanitized: `-` → `_`, lowercased → uppercased.
   - Resulting linker var:
     `CARGO_TARGET_<SANITIZED_TRIPLE>_LINKER`

3. **Wrapper creation**

   - Wrapper path in `${RUNNER_TEMP:-/tmp}/zig-wrappers`, created with `mktemp` when available for concurrency safety.
   - The wrapper script is a simple shell script:

     ```sh
     #!/bin/sh
     exec zig cc -target "$ZIG_TARGET" "$@"
     ```

   - Exported variables:
     - `CARGO_TARGET_<TRIPLE>_LINKER="$WRAPPER"`
     - `CC_<TRIPLE>="$CC_CMD"`
     - `CXX_<TRIPLE>="$CXX_CMD"`

Cargo then uses the wrapper as the linker for the configured target.

---

## 5. Verification Behavior

Verification is controlled by the `verify-level` input.

- `basic` (default):
  - After a successful build (and non-Windows host), the action runs:

    ```sh
    find . -maxdepth 3 -type f -not -path '*/.*' -exec file {} \; \
      | grep -i "ELF\|Mach-O\|PE32" \
      || echo "No obvious binaries found to verify."
    ```

  - This is a heuristic check to confirm that at least one binary artifact was produced.

- `none`:
  - Verification step is skipped entirely.

Callers who need strict checks (e.g. verifying exact architecture or dynamic vs static linking) are expected to implement additional steps in their workflows.

---

## 6. Testing Strategy

An E2E workflow validates core scenarios:

- Go (CGO) → `linux-arm64` (mapped to `aarch64-linux-musl`) on `ubuntu-latest`.
- Rust → `aarch64-unknown-linux-gnu` on `ubuntu-latest`.
- C → `windows-x64` (PE) on `ubuntu-latest`.
- C → `aarch64-macos` (Mach-O) on `macos-latest`.

Each job:

1. Checks out the repository.
2. Installs the relevant language toolchain (if needed).
3. Uses the action with appropriate `target` / `project-type`.
4. Verifies the resulting binary using `file` and a simple grep on the architecture or format.

This ensures the published action remains functional across its advertised targets.

---

## 7. Design Trade-offs

- **No Docker:** avoids complexity and performance issues of containerized toolchains; relies solely on Zig binaries plus the host runner.
- **Opinionated environment:** the action always overwrites `CC`, `CXX`, `AR`, `RANLIB`, and language-specific vars. This avoids ambiguous “merged” environments.
- **Root-only auto-detection:** simplifies logic and avoids expensive/ambiguous directory scans; monorepo scenarios are handled by explicit configuration.
- **Default Musl for Linux aliases:** favors static, distro-independent binaries at the cost of some complexity for Rust Musl targets (handled by `rust-musl-mode`).

This architecture is intended to remain stable across v2.x, with future changes focused on additional targets, documentation, and optional verification improvements.
