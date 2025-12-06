# Architecture & Technical Design

**Scope:** `zig-cross-compile-action` is an *infrastructure* component, not a build script. It prepares the environment (compiler, linker, OS flags) so that standard build tools (`go`, `cargo`, `make`, `cmake`) can cross-compile natively.

---

## 1. Core Philosophy

1.  **Zero Dependencies:** No Docker, no Python, no Node.js (in the core path). Just `bash` and the `zig` binary.
2.  **Opinionated:** We explicitly overwrite `CC`, `CXX` and target flags. Using this action implies you want Zig to handle compilation.
3.  **Fail Fast:** Invalid configurations (e.g. Windows host, misconfigured Rust+Musl) abort immediately with clear errors.

---

## 2. Infrastructure Layer

### 2.1 The Container-less Approach

Traditional cross-compilation relies on Docker containers (e.g. `dockcross`) or heavy sysroot setup (e.g. `apt-get install gcc-arm-linux-gnueabihf`).

This action uses Zig’s built-in `libc` (which bundles Musl, Glibc, Mingw-w64, and Apple SDK headers) to turn standard GitHub Runners (`ubuntu-latest`, `macos-latest`) into universal cross-compilers.

### 2.2 Component Diagram

```mermaid
flowchart LR
    User[User Workflow] --> Action[action.yml]
    Action --> SetupZig[setup-zig]
    Action --> SetupEnv[setup-env.sh]

    subgraph Environment Controller
        SetupEnv --> Detect[Project Type Detection]
        Detect -->|Auto/Go/Rust/C| Config[Export Env Vars]
        Config --> CC[CC="zig cc -target..."]
        Config --> CXX[CXX="zig c++ -target..."]
        Config --> GoEnv[GOOS/GOARCH/CGO]
        Config --> RustLink[CARGO_LINKER_WRAPPER]
    end

    subgraph Build Phase
        UserCmd[User Command] -->|Runs with| CC
        UserCmd -->|Runs with| GoEnv
    end
```

---

## 3. Implementation Details (`setup-env.sh`)

The bash script `setup-env.sh` is the engine. It performs:

### 3.1 Input Sanitization
- `target`: Cleaned to remove dangerous characters (only alphanumerics, dashes, dots allowed).
- `project-type`: validation against allowlist (`auto`, `go`, `rust`, `c`, `custom`).

### 3.2 Host Validation
- **Windows Host:** Explicitly **DENIED**.
  - `allow`: logs a note and proceeds.
    *Caveat:* This only guarantees that environment variables and the linker wrapper are set. It does **not** guarantee a successful link. Rust’s self-contained Musl CRT and Zig’s Musl CRT both attempt to define startup symbols (`_start`, `_init`), often resulting in duplicate symbol errors. This action will not inject flags to suppress this conflict.

### 3.3 Target Normalization
Maps user-friendly aliases to Zig targets:
- `linux-arm64` → `aarch64-linux-musl`
- `linux-x64` → `x86_64-linux-musl`
- `macos-arm64` → `aarch64-macos`
- `windows-x64` → `x86_64-windows-gnu`

### 3.4 Project Type Resolution
If `project-type: auto`:
1.  Check `Cargo.toml` (Root) → `rust`
2.  Check `go.mod` (Root) → `go`
3.  Default → `c`

**Monorepo Policy:** Auto-detection is strictly **root-only**. Separate documentation exists for monorepos (explicit configuration required).

### 3.5 Environment Configuration

#### Base Exports (All Types)
- `CC`, `CXX`, `AR`, `RANLIB` pointed to `zig`.
- `ZIG_TARGET` exported.

#### Go (CGO)
- Sets `CGO_ENABLED=1`.
- Derives `GOOS` / `GOARCH` from Zig target.

#### Rust
- Maps Zig triple to Rust triple.
- Creates a linker wrapper script in `${RUNNER_TEMP}/zig-wrappers` to satisfy Cargo's linker requirements.
- **Musl Policy:**
  - Default: `deny` (Rust bundled Musl vs Zig bundled Musl conflict risk).
  - Configurable via `rust-musl-mode`.

#### C / C++
- Explicitly sets `CGO_ENABLED=0` to ensure clean separation if Go tools happen to be present.

---

## 4. Strategic Roadmap (v3+)

### Tier 1 Expansion Plan

The long-term goal is to have 10–12 Tier 1 targets. Tier 2 is the staging area: targets start as “expected to work”, and graduate to Tier 1 once they have:

- a dedicated sample project in `examples/`,
- a job in `.github/workflows/e2e-test.yml`,
- and have been stable for at least one minor release.

Currently, candidates for promotion include `x86_64-linux-musl` and `x86_64-linux-gnu`.

See [TARGETS.md](./TARGETS.md) for the current definition of Tiers 1, 2, and 3.

---

## 5. Verification Design

The action supports a lightweight verification step (`verify-level`) to ensure "it compiles" implies "it produced a binary".

- **Level `basic` (Default):**
  - Runs `file` on output directory.
  - Greps for `ELF`, `PE32`, or `Mach-O`.
  - Intention: Catch silent build failures or misconfigured output paths.
- **Level `none`:**
  - Skips check (useful for non-binary artifacts or specialized verification).

---

## 6. Design Non-Goals

- **Orchestration:** We do *not* run build commands (`cargo build`). We only set the stage.
- **Package Management:** We do *not* install system libraries. Zig's static linking usually negates this need.
- **Windows Runners:** We do *not* support running the action on Windows.
