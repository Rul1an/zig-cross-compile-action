# Technical Design: Zig Cross-Compiler Action (v2.x)

**Status:** Production (v2.3.0)
**Philosophy:** Infrastructure, Not Helper
**Toolchain:** `zig cc`, `zig c++`

## 0. Context & Goals
`zig-cross-compile-action` is a Docker-free toolchain injector for GitHub Actions. **Current State (v2.3.0):**
*   **Zero Docker:** Runs directly on the host runner (Linux/macOS).
*   **Opinionated:** Unconditionally claims `$CC`, `$CXX`, `$AR`, `$RANLIB`.
*   **Strict Policies:** Hard fail on Windows hosts; opt-in only for Rust+Musl.
*   **Smart Automation:** Detects `Cargo.toml`/`go.mod` to apply correct environment policies.

**Goals:**
1.  **Transparency:** No hidden magic. Errors should be explicit and actionable.
2.  **Performance:** Zero container overhead.
3.  **Correctness:** Prefer explicit failure over "best effort" behavior that breaks silently.

## 1. Scope & Boundaries
To maintain maintainability and trust, we define strict boundaries.

### 1.1 In Scope
*   Cross-compiling C, C++, Rust, and Go binaries via Zig.
*   Mapping strict aliases (e.g., `linux-arm64`) to Zig triples (`aarch64-linux-musl`).
*   Injecting compiler environment variables into the GitHub Action job.

### 1.2 Non-Goals
*   **Build Orchestration:** We do not manage `go mod`, `cargo build`, or `make`. We provide the *compiler*; the user provides the *build command*.
*   **Toolchain Management:** We do not install Rust (rustup) or Go. That is the user's responsibility.
*   **Windows Host Support:** Bash on Windows (MSYS/Git Bash) is inconsistent. We only support Windows as a *target*, not a *host*.
*   **Project Mutation:** We never touch `Cargo.toml`, `.cargo/config`, or source files.

## 2. Architecture (v2.3.0)

### 2.1 Interface (`action.yml`)
| Input | Description | Default |
| :--- | :--- | :--- |
| `version` | Zig version (via `setup-zig`) | `0.13.0` |
| `target` | Compile target (alias or triple) | Required |
| `project-type` | Preset: `auto`, `go`, `rust`, `c`, `custom` | `auto` |
| `rust-musl-mode` | Policy: `deny`, `warn`, `allow` | `deny` |
| `cmd` | Build command to execute | Required |

### 2.2 Environment Controller (`setup-env.sh`)
The core logic script, sourced into the environment.

**Key Mechanics:**
*   **Shell Discipline:** `set -euo pipefail`. `safe_exit` handles sourcing vs execution.
*   **Platform Guard:** `die` if `RUNNER_OS == "Windows"`.
*   **Input Sanitization:** Strict regex on `TARGET`.
*   **Project Normalization:** `auto` detects `Cargo.toml` (Rust), `go.mod` (Go), else (C).
*   **Target Normalization:** Maps partial triples (`*unknown-linux-musl` -> `*linux-musl`) and aliases. Mappings favor Musl on Linux for static compatibility.
*   **Env Export:** Helpers for writing to `$GITHUB_ENV` (CI) or `export` (local).

## 3. Language-Specific Behavior

### 3.1 Go / CGO
*   **Trigger:** `project-type == go` (or auto-detected).
*   **Requirements:** Go toolchain pre-installed by user.
*   **Behavior:** Sets `CGO_ENABLED=1`, `GOOS`, `GOARCH` derived from Zig target.
*   **Note:** For pure Go (no CGO), use `custom` or set `CGO_ENABLED=0` manually.

### 3.2 Rust
*   **Trigger:** `project-type == rust` (or auto-detected).
*   **Musl Policy:** Zig's bundled Musl conflicts with Rust's bundled Musl CRT.
    *   `deny` (Default): Fail with error.
    *   `warn`: Log warning, proceed.
    *   `allow`: Log note, proceed.
*   **Linker Config:**
    *   Maps Zig targets to Rust triples (e.g., `aarch64-linux-musl` -> `aarch64-unknown-linux-musl`).
    *   Creates identifier-safe vars: `CARGO_TARGET_<TRIPLE>_LINKER`.
    *   **Wrapper:** Generates a script in `${RUNNER_TEMP}/zig-wrappers` using `mktemp` to handle spaces in linker args safely.

### 3.3 C / C++
*   **Trigger:** `project-type == c`.
*   **Behavior:** Sets `CC`, `CXX`. Explicitly sets `CGO_ENABLED=0` to isolate from accidental Go toolchain interactions.
*   *Decision:* For `type: c`, strictly `export CGO_ENABLED=0` to prevents accidental CGO usage if `go` is somehow invoked in a mixed repo.

### 2.4 Verification (`verify-level`)
*   **Default:** `basic` (Runs `file` check).
*   **None:** `none` (Skips check). Useful for monorepos or custom verification.

### 2.5 Monorepo Support
*   **Design Choice:** Auto-detection is Root-Only.
*   **Rationale:** Parsing directory trees for nested `Cargo.toml` is slow and error-prone. Users must be explicit in monorepos.

## 3. Technical Rationale

### 3.1 Why No Docker?
Avoids nested Docker issues, complex volume permissions, and performance overhead. Enables macOS support.

### 3.2 Opinionated Environment
We unconditionally overwrite `CC`, `CXX`, etc. Detailed mixing of "old" and "new" env vars leads to non-deterministic builds. Infrastructure must be authoritative.

## 5. Testing & Future Roadmap

### 5.1 E2E Matrix (Current)
*   **Go (CGO):** `linux-arm64` (Musl) on Ubuntu.
*   **Rust:** `aarch64-unknown-linux-gnu` (Glibc) on Ubuntu.
*   **C:** `windows-x64` (PE) on Ubuntu.
*   **C:** `macos-arm64` (Mach-O) on `macos-latest` (Added in v2.3).

### 5.2 Future Work (v3+)
*   **Verification:** Add `verify-level` (none, basic, precise) for stricter binary checks.
*   **Advanced Patterns:** Document CMake/Autotools/Make recipes (Done in v2.3).
*   **Debug Context:** Enhance debug logs with context blocks (Host OS, Target details).

---
**Summary:**
This action is production-ready code infrastructure. It minimizes "magic" in favor of predictable, standard-compliant behavior.
