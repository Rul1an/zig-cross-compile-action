# Changelog

Alle noemenswaardige wijzigingen aan deze Action worden in dit bestand bijgehouden.

Het formaat is geïnspireerd door [Keep a Changelog](https://keepachangelog.com/) en het project
volgt [Semantic Versioning](https://semver.org/).

## [Unreleased]

**Voorstellen / ideeën (nog niet geïmplementeerd):**

- Extra `verify-level: precise` voor strakkere binary-checks (bijvoorbeeld via `readelf` / `otool`).
- Uitgebreidere C-matrix in E2E (meer Tier-1 targets).
- Eventuele tweede Action specifiek voor Zig-installatie (TypeScript/Node-based).

---

## [2.4.3] – Marketplace Final Fix

**Gewijzigd**
- **Critical Fix:** `action.yml` uses correct `${{ ... }}` syntax for composite conditional.
- **Verified:** `setup-env.sh` shebang is `#!/usr/bin/env bash`.

## [2.4.2] – Final Polish

**Gewijzigd**
- Docs cleaned up (removed safe_exit refs, AI-isms).
- Contact info standardized to `info@logvault.eu`.
- Action branding applied (cpu/purple).

## [2.4.0] – Roadmap Execution

**Toegevoegd**
- `verify-level` input (`none` | `basic`).
- Enhanced Rust+Musl error messages with fix suggestions.
- Debug logging shows `cargo version` if present.
- Documentation for Monorepos and Caching.

## [2.3.0] – macOS verification & polish

**Toegevoegd**

- E2E-job `C macos-arm64` op `macos-latest`:
  - Bouwt een simpele C-binary met `target: aarch64-macos`.
  - Verifieert output via `file` op Mach-O formaat.

**Gewijzigd**

- `project-type: c` zet nu expliciet `CGO_ENABLED=0`, zodat C-builds geen last hebben van een
  aanwezige Go-toolchain in mixed repositories.
- README uitgebreid met praktische integratievoorbeelden:
  - CMake (`CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`)
  - Autotools (`./configure --host=$ZIG_TARGET`)
  - Make (`make CC="$CC" CXX="$CXX"`)
- ARCHITECTURE.md aangewezen als “single source of truth” voor het interne ontwerp en beleid.

---

## [2.2.0] – Design & documentation hardening

**Toegevoegd**

- Uitgebreide technische documentatie:
  - `ARCHITECTURE.md` met:
    - Scope & non-goals
    - Input-contract (`target`, `project-type`, `rust-musl-mode`, `cmd`)
    - Beschrijving van de environment controller (`setup-env.sh`)
- Duidelijke beschrijving van:
  - “Infrastructure, not helper”-filosofie.
  - Opinionated omgeving (bewust overschrijven van `CC`, `CXX`, `AR`, `RANLIB`, etc.).

**Gewijzigd**

- Documentatie rond auto-detect van `project-type`:
  - Legt uit dat auto-detect alleen de **repo root** inspecteert (`Cargo.toml`, `go.mod`).
  - Aanbevolen patterns voor monorepo’s toegevoegd (expliciet `project-type` zetten of
    `working-directory` aanpassen in de workflow).

---

## [2.1.0] – Production hardening

**Toegevoegd**

- Hard policy voor Windows host-runners:
  - Builds falen nu expliciet als `RUNNER_OS == Windows`.
  - Windows blijft ondersteund als *target* (`x86_64-windows-gnu`), niet als host.
- Rust+Musl policy:
  - Nieuwe input `rust-musl-mode`:
    - `deny` (default): Rust+Musl builds falen met een duidelijke foutmelding en suggesties.
    - `warn`: laat de build door maar logt een waarschuwing.
    - `allow`: ondersteunt Rust+Musl “as is”, met waarschuwing voor mogelijke CRT-conflicten.
- Debug logging via `ZIG_ACTION_DEBUG=1`:
  - Extra env-dump van relevante variabelen (`ZIG_*`, `GO*`, `CARGO_*`, `CC`, `CXX`).
  - Logt ook `cargo version` indien beschikbaar.

**Gewijzigd**

- Logging geüniformeerd naar GitHub Action log-annotaties:
  - `::notice::[zig-action] ...`
  - `::debug::[zig-action] ...`
  - `::error::[zig-action] ...`
- Rust-linker wrapper:
  - Wrapper scripts worden nu in `${RUNNER_TEMP}/zig-wrappers` met `mktemp` aangemaakt,
    zodat parallel builds voor meerdere targets in één job elkaar niet in de weg zitten.

---

## [2.0.0] – Initial v2 release

> Let op: exacte details van v2.0.0 kunnen afwijken; deze sectie beschrijft de grote lijnen
> van de eerste stabiele v2-serie.

**Toegevoegd**

- Eerste stabiele compositie van de Action:
  - `action.yml` met inputs:
    - `version`
    - `target`
    - `project-type`
    - `cmd`
  - `setup-env.sh` met:
    - Target-aliasing (bijv. `linux-arm64` → `aarch64-linux-musl`).
    - Basis-env exports:
      - `CC="zig cc -target ..."`
      - `CXX="zig c++ -target ..."`
      - `AR="zig ar"`
      - `RANLIB="zig ranlib"`
- Eenvoudige heuristische verificatie:
  - `find . -maxdepth ... | file` om ELF/Mach-O/PE-binaries te detecteren.
- Basis support voor:
  - Go (CGO) via `CGO_ENABLED`, `GOOS`, `GOARCH`.
  - Rust via `CARGO_TARGET_<TRIPLE>_LINKER` wrapper.
  - C/C++ via `$CC` / `$CXX`.

---

## [1.x.x] – Legacy

De 1.x-serie was de oorspronkelijke experimentele variant van de Action, vóór de huidige
production-grade policies (geen Windows host, stricte Rust+Musl regels, debug-mode, enz.).

Nieuwe projecten wordt aangeraden **minstens v2** te gebruiken en bij voorkeur
naar de laatste `v2.x` te pinnen.
