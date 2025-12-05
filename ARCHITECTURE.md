# Architecture: Zig Cross-Compiler Action

## Core Principle
Eliminates Docker storage/CPU overhead by using Zig's toolchain (`zig cc`, `zig c++`) as a drop-in C/C++ cross-compiler. Zig bundles libc source (musl, glibc) and headers for multiple architectures, allowing reliable cross-compilation from a standard runner.

## Components

### 1. Interface (`action.yml`)
Composite action.
- **Inputs**: `target` (required), `cmd` (required), `version` (default: 0.13.0), `project-type`.
- **Execution**:
    1. **Setup**: Sources `setup-env.sh` to mutate the environment.
    2. **Install**: Installs Zig toolchain via `goto-bus-stop/setup-zig`.
    3. **Build**: Executes user `cmd` directly in the shell (no `eval` or extra `bash -c` wrapper).
    4. **Verify**: Heuristic verification (checks for binary format) if not on Windows.

### 2. Logic Controller (`setup-env.sh`)
Bash script responsible for environment mutation.

#### Safety & robustness
- **Mode**: Runs with `set -euo pipefail` for strict error handling and undefined variable detection.
- **Sourcing**: Detects if it is being sourced. In CI, errors fall through to fail the step. Lokaal usage is guarded with warnings.
- **Sanitization**: `target` input is regex-validated `^[a-zA-Z0-9_\.-]+$` to prevent injection.

#### Target Aliasing
Maps CI-friendly names to canonical Zig compilation targets using `case` statements.
- `linux-arm64` -> `aarch64-linux-musl` (Static default)
- `macos-arm64` -> `aarch64-macos`

#### Compiler Injection
Exports standard make/build variables via `$GITHUB_ENV`.
```bash
export CC="zig cc -target $ZIG_TARGET"
export CXX="zig c++ -target $ZIG_TARGET"
export AR="zig ar"
export RANLIB="zig ranlib"
```

#### Language Specifics

**Go (CGO)**
- Triggered if `project-type` is `go` or `auto`.
- Sets `CGO_ENABLED=1`.
- Infers `GOOS` and `GOARCH` from the Zig target string.

**Rust**
- Triggered if `project-type` is `rust` or `auto`.
- **Constraint**: Cargo linker arguments cannot handle spaces (e.g., `zig cc -target ...`).
- **Solution**: Generates a wrapper script in `${RUNNER_TEMP}/zig-wrappers/cc-<target>`.
- **Triple Mapping**:
    - Maps Zig targets to Rust conventions (e.g., `aarch64-linux-musl` -> `aarch64-unknown-linux-musl`).
    - Skips configuration if target contains a version suffix (e.g. `.2.31`) to prevent invalid environment variable names.
- **Export**: `CARGO_TARGET_<SANITIZED_TRIPLE>_LINKER=/path/to/wrapper`.
- **Note**: Does *not* install the rust target or run cargo; the user remains responsible for `rustup target add`.

## Verification
Post-build check runs `find` and `file` on artifacts to confirm correct architecture (ELF/Mach-O), guarded by `runner.os != 'Windows'`.
