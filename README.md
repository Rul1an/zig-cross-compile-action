# zig-cross-compile-action

A composite GitHub Action for cross-compiling C, C++, Rust, and Go using Zig.
No Docker containers required. Uses Zig's `cc` and `c++` as drop-in compilers, automatically configuring the required environment variables.

## Why
Cross-compiling with Docker is slow and file-permissions are often broken. `cross-rs` is heavy.
Zig ships with its own libc and linker, allowing specific targets (like `linux-musl` or simple `macos` binaries) to build on a standard runner.

> **Note**: macOS cross-compilation works for simple CLI binaries/libs. Full macOS apps requiring Apple Frameworks/SDKs still need a macOS runner.

## Usage
This action follows the "Infrastructure, Not Helper" philosophy.
**It does NOT:**
- Install Rust or Go toolchains (use `dtolnay/rust-toolchain` or `actions/setup-go`).
- Run `go mod init` or `rustup target add`.
- Modify your project files.

**It DOES:**
- Install Zig.
- Configure environment variables to force cross-compilation via `zig cc`.

### Go (CGO)
Configuration `project-type: auto` enables CGO (`CGO_ENABLED=1`) for Linux/macOS targets automatically.
If you need a pure Go binary (no CGO), set `project-type: custom` or unset `CGO_ENABLED` manually.

```yaml
- uses: ./zig-action
  with:
    target: linux-arm64
    cmd: go build -o dist/app ./cmd
```

### Rust
We configure the `CARGO_TARGET_..._LINKER` variables.
**Note**: `*-musl` targets are disabled by default due to CRT conflicts. To enable them (at your own risk), set `rust-musl-mode: warn` or `allow`.

```yaml
- uses: dtolnay/rust-toolchain@stable
  with:
    targets: aarch64-unknown-linux-gnu

- uses: ./zig-action
  with:
    target: aarch64-unknown-linux-gnu
    rust-musl-mode: deny # default
    cmd: cargo build --release --target aarch64-unknown-linux-gnu
```

### C/C++
```yaml
- uses: ./zig-action
  with:
    target: windows-x64
    cmd: $CC main.c -o app.exe
```

### Inputs

| Input | Description | Required | Default | Options |
| :--- | :--- | :--- | :--- | :--- |
| `version` | Zig version to install. | `false` | `0.13.0` | Any valid Zig version |
| `target` | Target architecture. | `true` | - | e.g. `linux-arm64` |
| `cmd` | Command to execute. | `true` | - | e.g. `go build ...` |
| `project-type` | Language preset. | `false` | `auto` | `auto`, `go`, `rust`, `c`, `custom` |
| `rust-musl-mode` | Policy for Rust+Musl. | `false` | `deny` | `deny`, `warn`, `allow` |

### Environment & Runners

**Supported Runners:**
- `ubuntu-latest` (Tier 1 Support)
- `macos-latest` (Tier 1 Support)
- **Windows Runners**: NOT SUPPORTED. The action will fail immediately on Windows hosts.

**Verified Targets:**
- `x86_64-linux-musl`, `aarch64-linux-musl`
- `aarch64-unknown-linux-gnu`
- `x86_64-windows-gnu`
- `aarch64-macos`, `x86_64-macos`

*Other compiled targets may work but are considered "best effort".*

**Environment Variables ("Opinionated Environment"):**
This action treats the build environment as its own domain. It will **unconditionally overwrite**:
- `CC`, `CXX`, `AR`, `RANLIB`
- `ZIG_TARGET`
- `CGO_ENABLED`, `GOOS`, `GOARCH` (for Go projects)
- `CARGO_TARGET_<TRIPLE>_LINKER`, `CC_<TRIPLE>`, `CXX_<TRIPLE>` (for Rust projects)

To enable debug logging, set `ZIG_ACTION_DEBUG: 1`.

### Integration Patterns
Common build systems integration strategies:

**CMake:**
```bash
cmake -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" ...
```

**Autotools (configure):**
```bash
./configure CC="$CC" CXX="$CXX" --host=$ZIG_TARGET
```

**Make:**
```bash
make CC="$CC" CXX="$CXX"
```

```bash
make CC="$CC" CXX="$CXX"
```

### Monorepo Usage
`project-type: auto` only checks the repository root. For monorepos:
1. Set `project-type: rust` or `go` explicitly.
2. Or use `working-directory` in your job steps.

```yaml
- uses: ./zig-action
  with:
    project-type: rust
    cmd: cd services/my-service && cargo build --release
```

### Caching (Optional)
This action is cache-agnostisch. To speed up builds, use `actions/cache`:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/zig
    key: zig-${{ runner.os }}-${{ inputs.target }}
```

### Aliases & Defaults
We map convenience aliases to "safe defaults" (usually static Musl for Linux).
If you need **glibc** or specific versions, use the full Zig target triple (e.g. `x86_64-linux-gnu.2.31`).

* `linux-arm64` -> `aarch64-linux-musl` (Static binary default)
* `linux-x64`   -> `x86_64-linux-musl`
* `macos-arm64` -> `aarch64-macos`
* `macos-x64`   -> `x86_64-macos`
* `windows-x64` -> `x86_64-windows-gnu`
```
