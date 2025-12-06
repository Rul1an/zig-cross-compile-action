# Supported Targets

Dit document beschrijft welke targets expliciet ondersteund en getest worden door
`zig-cross-compile-action`, en hoe strikt die support is.

We verdelen targets in drie “tiers”:

- **Tier 1 – Verified:**
  Worden automatisch getest in de E2E-workflow. Verwacht dat deze combinaties stabiel werken.
- **Tier 2 – Expected:**
  Worden niet in elke commit getest, maar zijn bekende en courante Zig-targets die in de praktijk
  goed werken. Issues zijn mogelijk; PR’s welkom.
- **Tier 3 – Best effort / exotic:**
  Door Zig ondersteund, maar niet door deze Action actief getest. Gebruik op eigen risico.

> Let op: deze Action ondersteunt **alleen Linux en macOS als host**.
> Windows is alleen ondersteund als *target*, niet als *runner*.

---

## Tier 1 – Verified in CI

Deze targets worden bouwtechnisch gevalideerd in `.github/workflows/e2e-test.yml`.

| Target triple                 | Alias          | Host runner     | Taal / Use case            | Status      |
| ---------------------------- | -------------- | --------------- | -------------------------- | ----------- |
| `aarch64-linux-musl`         | `linux-arm64`  | `ubuntu-latest` | Go (CGO) cross-build       | ✅ Verified |
| `aarch64-unknown-linux-gnu`  | —              | `ubuntu-latest` | Rust cross-build           | ✅ Verified |
| `x86_64-windows-gnu`         | `windows-x64`  | `ubuntu-latest` | C → Windows PE64           | ✅ Verified |
| `aarch64-macos`              | `macos-arm64`  | `macos-latest`  | C → macOS ARM64 (Mach-O)   | ✅ Verified |

**Garanties:**

- Deze combinaties worden in de E2E-workflow gebouwd én via `file` gecontroleerd op de juiste
  architectuur / binary type.
- Regressies op deze targets worden als **bugs** gezien en bij voorkeur in een patchrelease
  opgelost.

---

## Tier 2 – Expected to work

Targets die sterk lijken op Tier 1, of door Zig goed ondersteund worden, maar nog niet expliciet
in de E2E-matrix zitten.

| Target triple                 | Mogelijke alias     | Verwacht host        | Opmerkingen                                                   |
| ---------------------------- | ------------------- | -------------------- | ------------------------------------------------------------- |
| `x86_64-linux-musl`          | `linux-x64`         | `ubuntu-latest`      | Statisch Linux x64, ideaal voor “glue-free” distributables.  |
| `x86_64-linux-gnu`           | —                   | `ubuntu-latest`      | Glibc Linux x64, voor klassieke distro-compatibiliteit.      |
| `x86_64-macos`               | `macos-x64`         | `macos-latest`       | macOS Intel, vergelijkbaar met `aarch64-macos`.              |
| `armv7-linux-gnueabihf`      | —                   | `ubuntu-latest`      | 32-bit ARM (older Pi / embedded).                            |
| `riscv64-linux-gnu`          | —                   | `ubuntu-latest`      | RISC-V 64-bit, up-and-coming architectuur.                   |

**Richtlijn:**

- Als het target qua vorm lijkt op een Tier-1 target en door Zig ondersteund wordt, mag je
  redelijkerwijs verwachten dat de Action werkt.
- Zie je issues op deze targets, open gerust een issue met:
  - Host OS
  - Zig versie
  - Target triple
  - Build command + volledige linker error

---

## Tier 3 – Best effort / exotic

Voorbeelden van meer exotische Zig-targets die *theoretisch* moeten werken, maar niet in deze repo
geautomatiseerd getest worden:

| Target triple                 | Type               |
| ---------------------------- | ------------------ |
| `powerpc64le-linux-gnu`      | IBM POWER          |
| `s390x-linux-gnu`            | IBM Z / mainframe  |
| …                            | …                  |

Use-case: niche deployments, HPC, mainframe. Hier geldt: als Zig het target ondersteunt, zorgt de
Action er *alleen* voor dat `CC` / `CXX` en de relevante env-vars goed gezet worden. Extra toolchain
en sysroot-issues vallen buiten scope.

---

## Target aliasing

De Action ondersteunt een aantal human-friendly aliases, die omgezet worden naar Zig-targets:

| Alias          | Zig target triple      |
| -------------- | ---------------------- |
| `linux-arm64`  | `aarch64-linux-musl`   |
| `linux-aarch64`| `aarch64-linux-musl`   |
| `linux-x64`    | `x86_64-linux-musl`    |
| `linux-amd64`  | `x86_64-linux-musl`    |
| `macos-arm64`  | `aarch64-macos`        |
| `darwin-arm64` | `aarch64-macos`        |
| `macos-x64`    | `x86_64-macos`         |
| `darwin-amd64` | `x86_64-macos`         |
| `windows-x64`  | `x86_64-windows-gnu`   |
| `windows-amd64`| `x86_64-windows-gnu`   |

Wil je heel specifiek zijn (bijvoorbeeld een bepaalde glibc-versie), gebruik dan de volledige Zig
target triple, zoals `x86_64-linux-gnu.2.31`. Let wel: Rust-integratie wordt alleen automatisch
geconfigureerd voor targets **zonder** versie suffix.

---

## Host OS support

- ✅ **Ubuntu (Linux) runners** – volledig ondersteund
- ✅ **macOS runners** – volledig ondersteund
- ❌ **Windows runners** – worden actief geweigerd als host (`RUNNER_OS == Windows` → hard fail)

Windows is uitsluitend ondersteund als *target* (via `x86_64-windows-gnu`), niet als platform waarop
de Action zelf draait.
