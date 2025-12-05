# Architecture: Zig Cross-Compiler Action

## Core Principle
Eliminates Docker storage/CPU overhead by using Zig's toolchain (`zig cc`, `zig c++`) as a drop-in C/C++ cross-compiler. Zig bundles libc source (musl, glibc) and headers for multiple architectures, allowing reliable cross-compilation from a standard runner.

## Components

### 1. Interface (`action.yml`)
Composite action.
- **Inputs**: `target` (required), `cmd` (required), `version` (default: 0.13.0).
- **Execution**:
    1. Runs logic script (`setup-env.sh`).
    2. Installs Zig toolchain.
    3. Executes user `cmd`.
    4. Heuristic verification (checks for binary format).

### 2. Logic Controller (`setup-env.sh`)
Bash script responsible for environment mutation. POSIX-compliant for macOS compatibility.

#### Target Aliasing
Maps CI-friendly names to canonical Zig compilation targets using `case` statements (avoids bash 4.0 dependency).
- `linux-arm64` -> `aarch64-linux-musl` (Static default)
- `macos-arm64` -> `aarch64-macos`

#### Compiler Injection
Exports standard make/build variables to force the build system to use Zig.
```bash
export CC="zig cc -target $ZIG_TARGET"
export CXX="zig c++ -target $ZIG_TARGET"
export AR="zig ar"
export RANLIB="zig ranlib"
```

#### Language Specifics

**Go (CGO)**
- Sets `CGO_ENABLED=1`.
- Infers `GOOS` and `GOARCH` from the Zig target string.
- `go build` automatically picks up the exported `$CC` for C dependencies.

**Rust**
Cargo fails if the linker environment variable contains spaces/arguments (e.g., `zig cc -target ...`).
- **Workaround**: We generate a shell wrapper script in `${RUNNER_TEMP}/zig-wrappers/cc-<target>`.
- **Logic**: wrapper executes `exec zig cc -target <target> "$@"`.
- **Export**: `CARGO_TARGET_<TRIPLE>_LINKER=/path/to/wrapper`.

## Security & Robustness
- **Input Sanitization**: `target` input is regex-validated `^[a-zA-Z0-9_\.-]+$` to prevent generic shell injection in `eval` contexts.
- **Shell Safety**: `set -eo pipefail` ensures immediate failure on errors.
- **Verification**: Post-build check runs `file` on artifacts to confirm correct architecture (ELF/Mach-O).
