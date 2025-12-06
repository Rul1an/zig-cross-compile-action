# Target Support Levels

This document describes which targets are supported by `zig-cross-compile-action` and how strongly they are supported.

The key idea:

- **Tier 1**: in CI, tested on every push and release.
- **Tier 2**: expected to work, close to Tier 1, but not in the default E2E matrix.
- **Tier 3**: best-effort; Zig knows the target, but this action does not have regular coverage for it.

If you rely on a target in production, you should either pick a Tier-1 target or add your own verification job on top of what this action provides.

---

## 1. Tiers at a glance

| Tier  | Guarantee level                    | CI coverage                        | Typical use                                       |
| ----- | ---------------------------------- | ---------------------------------- | ------------------------------------------------- |
| 1     | “Supported”                        | In `.github/workflows/e2e.yml`     | Default choice for most users                     |
| 2     | “Expected to work”                 | Tested occasionally / manually     | Extra platforms for advanced users                |
| 3     | “Best-effort / compiles locally”   | No guarantees                      | Experiments, niche platforms, local validation    |

Targets can move from Tier 2 to Tier 1 once they have a dedicated example and a stable CI job.

---

## 2. Tier 1 – Fully supported (E2E tested)

Tier-1 targets are exercised on every push and on tagged releases via the `E2E Verification` workflow. Each row includes:

- The effective Zig target.
- Any alias the action understands.
- The host runner used in CI.
- The example project that is built for that target.

| Language / scenario      | Target triple              | Alias         | Host runner      | Example / CI job                         | Notes                                             |
| ------------------------ | -------------------------- | ------------- | ---------------- | ---------------------------------------- | ------------------------------------------------- |
| Go (CGO) → Linux ARM64   | `aarch64-linux-musl`       | `linux-arm64` | `ubuntu-latest`  | `examples/go-cgo`, `test-go-arm64`       | Static Linux ARM64 binary built with CGO.         |
| Rust → Linux ARM64 (GNU) | `aarch64-unknown-linux-gnu`| —             | `ubuntu-latest`  | `examples/rust-aarch64`, `test-rust-gnu` | Uses Zig as linker for the Rust target.           |
| C → Linux x64 (Musl)     | `x86_64-linux-musl`        | `linux-x64`   | `ubuntu-latest`  | `examples/c-linux-musl`, `test-c-linux`  | Static Linux x64, Alpine compatible.              |
| C → Linux x64 (GNU)      | `x86_64-linux-gnu`         | —             | `ubuntu-latest`  | `examples/c-linux-gnu`, `test-c-linux`   | Standard Glibc Linux x64.                         |
| C → Windows x64          | `x86_64-windows-gnu`       | `windows-x64` | `ubuntu-latest`  | `examples/c-windows`, `test-c-windows`   | PE64 exe built from a Linux host.                 |
| C → macOS ARM64          | `aarch64-macos`            | —             | `macos-latest`   | `examples/c-macos`, `test-c-macos`       | Mach-O ARM64 CLI binary on macOS runner.          |

If you want a target that “just works” with this action, pick one of these or a close variant and mirror the corresponding E2E job in your own repo.

---

## 3. Tier 2 – Expected to work

Tier-2 targets are either:

- Close relatives of Tier-1 targets, or
- Well supported by Zig, but not yet wired into the default E2E matrix.

They are good candidates for promotion to Tier 1 in future releases. If you depend on one of these in production, it is recommended to add your own verification job (for example a small C or Rust example that runs `file` on the output).

| Target triple              | Alias        | Expected host      | Notes                                                              |
| -------------------------- | ----------- | ------------------ | ------------------------------------------------------------------ |
| `x86_64-macos`             | `macos-x64` | `macos-latest`     | Intel macOS, symmetric to the Tier-1 `aarch64-macos` case.         |
| `armv7-linux-gnueabihf`    | —           | `ubuntu-latest`    | 32-bit ARM (older Raspberry Pi / embedded).                        |
| `riscv64-linux-gnu`        | —           | `ubuntu-latest`    | RISC-V 64-bit, useful for experimentation and early adopters.      |

In practice, most of these targets can be exercised by copying one of the existing E2E jobs and changing the `target` plus verification step.

> **Note:** `x86_64-linux-gnu` and `x86_64-linux-musl` were promoted to Tier 1 in v2.6.0 (Tier 1 Expansion) after E2E verification.

---

## 4. Tier 3 – Best-effort / niche targets

Tier-3 targets are Zig targets that this action can in principle drive, but that are not part of any regular CI workflow for this repository. That includes:

- Less common server and mainframe architectures (for example `powerpc64le-linux-gnu`, `s390x-linux-gnu`).
- Experimental or rarely used embedded targets.
- Any target that requires extra SDKs or vendor tooling beyond Zig and a standard runner.

A straightforward sanity check for these is:

1. Use this action to set up the environment for the desired target.
2. Compile a small C program using `$CC`.
3. Run `file` on the resulting binary on the host, and then test it on real hardware or an appropriate emulator.

If you find a Tier-3 target that behaves reliably across multiple projects, it can be proposed for Tier-2 (and eventually Tier-1) by opening an issue with details of your setup.

---

## 5. Promotion rules

Targets move between tiers based on evidence, not intent. A target is promoted to Tier-1 once all of the following are true:

- There is a minimal example in `examples/` that builds for that target.
- There is a dedicated job in `.github/workflows/e2e.yml` that uses this action to build that example and verifies the binary format with `file`.
- The job has been stable for at least one minor release (no flaky behavior, no recurrent regressions).

Tier-2 is used as the staging area: if a target is frequently used and reports are positive, the next step is to add it to the matrix, not to keep it indefinitely as “expected to work”.

---

## 6. Host runners and limitations

This action supports:

- `ubuntu-latest` as a Tier-1 host.
- `macos-latest` as a Tier-1 host.

Windows is supported as a **target only**, not as a host. On Windows runners the action will fail fast with a clear error.

Some targets have additional limitations that are not specific to this action but to Zig or the underlying platform. Examples:

- macOS cross-compilation from Linux is limited; for non-trivial apps you still need Apple’s SDKs on a macOS host.
- Rust with Musl is intentionally blocked by default here because of CRT conflicts between Rust’s Musl runtime and Zig’s Musl implementation.

Those constraints are documented in more detail in `ARCHITECTURE.md` and in the README.

---

## 7. Keeping this document up-to-date

This file is meant to be the single reference for target support policy.

When you:

- Add a new E2E job for a target, update the Tier-1 table.
- Start recommending a new target that is not in the matrix, add it to Tier-2.
- Experiment with an unusual architecture and confirm it compiles, consider listing it in Tier-3 with a short note.

Small, concrete updates here help users understand what they can rely on today and what is still in the “experimental” bucket.
