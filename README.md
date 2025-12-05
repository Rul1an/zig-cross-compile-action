# zig-cross-compile-action

A composite GitHub Action for cross-compiling C, C++, Rust, and Go using Zig.
No Docker containers required. Uses Zig's `cc` and `c++` as drop-in compilers, automatically configuring the required environment variables.

## Why
Cross-compiling with Docker is slow and file-permissions are often broken. `cross-rs` is heavy.
Zig ships with its own libc and linker, allowing specific targets (like `linux-musl` or simple `macos` binaries) to build on a standard runner.

> **Note**: macOS cross-compilation works for simple CLI binaries/libs. Full macOS apps requiring Apple Frameworks/SDKs still need a macOS runner.

## Usage

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
**Note**: Only `*-gnu` targets (glibc) are fully supported. `*-musl` targets are experimental due to potential CRT conflicts between Zig and Rust's self-contained Musl.

```yaml
- uses: dtolnay/rust-toolchain@stable
  with:
    targets: aarch64-unknown-linux-gnu

- uses: ./zig-action
  with:
    target: aarch64-unknown-linux-gnu
    cmd: cargo build --release --target aarch64-unknown-linux-gnu
```

### C/C++
```yaml
- uses: ./zig-action
  with:
    target: windows-x64
    cmd: $CC main.c -o app.exe
```

## Inputs

| Input | Description | Default |
| :--- | :--- | :--- |
| `target` | Zig target (e.g. `x86_64-linux-musl`) or alias | **Required** |
| `cmd` | Command to run in the configured environment | **Required** |
| `version` | Zig version (uses `goto-bus-stop/setup-zig`) | `0.13.0` |
| `project-type` | `go`, `rust`, `c`, `auto`, or `custom` | `auto` |

### Aliases & Defaults
We map convenience aliases to "safe defaults" (usually static Musl for Linux).
If you need **glibc** or specific versions, use the full Zig target triple (e.g. `x86_64-linux-gnu.2.31`).

* `linux-arm64` -> `aarch64-linux-musl` (Static binary default)
* `linux-x64`   -> `x86_64-linux-musl`
* `macos-arm64` -> `aarch64-macos`
* `macos-x64`   -> `x86_64-macos`
* `windows-x64` -> `x86_64-windows-gnu`
```
