# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

**Proposals / Ideas (Not yet implemented):**

- Extra `verify-level: precise` for stricter binary checks (e.g., via `readelf` / `otool`).
- Expanded C-matrix in E2E (more Tier-1 targets).
- Potential second Action specifically for Zig installation (TypeScript/Node-based).

---

## [2.5.0] – Validation & Tiers

**Added**
- **Validation Suite:** dedicated `tests/` directory with dummy projects and `verify-action.yml`.
- **Tier 1 Definition:** Formalized `aarch64-unknown-linux-gnu` (Rust) and other targets as supported Tier-1 paths.

**Changed**
- **Rust Validation:** Switched E2E to verify `aarch64-unknown-linux-gnu` (success path) instead of Musl.
- **Musl Policy:** Explicitly document that `rust-musl-mode: allow` only guarantees environment wiring, not binary linking (due to CRT conflicts).
- **Windows Tests:** Fixed `test-c-windows` by ensuring the output directory exists.

## [2.4.3] – Marketplace Final Fix

**Changed**
- **Critical Fix:** `action.yml` uses correct `${{ ... }}` syntax for composite conditional.
- **Verified:** `setup-env.sh` shebang is `#!/usr/bin/env bash`.

## [2.4.2] – Final Polish

**Changed**
- Docs cleaned up.
- Contact info standardized to `info@logvault.eu`.
- Action branding applied.

## [2.4.0] – Roadmap Execution

**Added**
- `verify-level` input (`none` | `basic`).
- Enhanced Rust+Musl error messages with fix suggestions.
- Debug logging shows `cargo version` if present.
- Documentation for Monorepos and Caching.

## [2.3.0] – macOS verification & polish

**Added**

- E2E-job `C macos-arm64` on `macos-latest`:
  - Builds a simple C binary with `target: aarch64-macos`.
  - Verifies output via `file` for Mach-O format.
- New input `verify-level`:
  - `basic` (default): runs a lightweight `file` scan on binaries in the workspace.
  - `none`: skips the verify step entirely.

**Changed**

- `project-type: c` now explicitly sets `CGO_ENABLED=0`, so C-builds are not affected by a Go toolchain in mixed repositories.
- README expanded with practical integration examples:
  - CMake (`CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`)
  - Autotools (`./configure --host=$ZIG_TARGET`)
  - Make (`make CC="$CC" CXX="$CXX"`)
- ARCHITECTURE.md designated as the “single source of truth” for internal design and policy.

---

## [2.2.0] – Design & documentation hardening

**Added**

- Comprehensive technical documentation:
  - `ARCHITECTURE.md` containing:
    - Scope & non-goals
    - Input contract (`target`, `project-type`, `rust-musl-mode`, `cmd`)
    - Description of the environment controller (`setup-env.sh`)
- Clear description of:
  - “Infrastructure, not helper” philosophy.
  - Opinionated environment (deliberately overwriting `CC`, `CXX`, `AR`, `RANLIB`, etc.).

**Changed**

- Documentation around `project-type` auto-detection:
  - Explains that auto-detect only inspects the **repo root** (`Cargo.toml`, `go.mod`).
  - Added recommended patterns for monorepos (setting `project-type` explicitly or adjusting `working-directory` in the workflow).

---

## [2.1.0] – Production hardening

**Added**

- Hard policy for Windows host-runners:
  - Builds now fail explicitly if `RUNNER_OS == Windows`.
  - Windows remains supported as a *target* (`x86_64-windows-gnu`), not as a host.
- Rust+Musl policy:
  - New input `rust-musl-mode`:
    - `deny` (default): Rust+Musl builds fail with a clear error message and suggestions.
    - `warn`: allows the build but logs a warning.
    - `allow`: supports Rust+Musl “as is”, with a warning about possible CRT conflicts.
- Debug logging via `ZIG_ACTION_DEBUG=1`:
  - Extra env-dump of relevant variables (`ZIG_*`, `GO*`, `CARGO_*`, `CC`, `CXX`).
  - Also logs `cargo version` if available.

**Changed**

- Logging unified to GitHub Action log annotations:
  - `::notice::[zig-action] ...`
  - `::debug::[zig-action] ...`
  - `::error::[zig-action] ...`
- Rust-linker wrapper:
  - Wrapper scripts are now created in `${RUNNER_TEMP}/zig-wrappers` using `mktemp`, preventing conflicts between parallel builds for multiple targets in a single job.

---

## [2.0.0] – Initial v2 release

> Note: Exact details of v2.0.0 may vary; this section describes the broad strokes of the first stable v2 series.

**Added**

- First stable composition of the Action:
  - `action.yml` with inputs:
    - `version`
    - `target`
    - `project-type`
    - `cmd`
  - `setup-env.sh` with:
    - Target aliasing (e.g. `linux-arm64` → `aarch64-linux-musl`).
    - Base env exports:
      - `CC="zig cc -target ..."`
      - `CXX="zig c++ -target ..."`
      - `AR="zig ar"`
      - `RANLIB="zig ranlib"`
- Simple heuristic verification:
  - `find . -maxdepth ... | file` to detect ELF/Mach-O/PE binaries.
- Basic support for:
  - Go (CGO) via `CGO_ENABLED`, `GOOS`, `GOARCH`.
  - Rust via `CARGO_TARGET_<TRIPLE>_LINKER` wrapper.
  - C/C++ via `$CC` / `$CXX`.

---

## [1.x.x] – Legacy

The 1.x series was the original experimental variant of the Action, before the current production-grade policies (no Windows host, strict Rust+Musl rules, debug-mode, etc.) were established.

New projects are advised to use **at least v2** and preferably pin to the latest `v2.x`.
