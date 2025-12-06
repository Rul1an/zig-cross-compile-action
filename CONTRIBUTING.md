# Contributing

We welcome contributions!

## Pull Request Process

1.  **Fork** the repo and create your branch from `main`.
2.  **Test** your changes locally if possible.
3.  **Ensure** you do not break existing E2E workflows.
4.  **Submit** a PR.

## Development

*   **Logic:** `setup-env.sh` contains the core logic.
*   **Tests:** `examples/` contains sample projects used by `.github/workflows/e2e-test.yml`.

## Style Guide

*   Use `bash` for scripts (avoid sh-isms where bash is safer, but keep it portable enough for standard runners).
*   Prefer `die "message"` over `exit 1`.
*   Keep dependencies zero.

## Release Process

We follow [Semantic Versioning](https://semver.org/).

### 1. Marketplace vs. Repository
*   **Documentation:** The Marketplace page shows the `README.md` from the **default branch (`main`)**. Updating docs does NOT require a new release; just push to main.
*   **Versioning:** The Marketplace version dropdown is synced with GitHub Release tags (e.g., `v2.4.3`).

### 2. Creating a Release
To publish a new version:

1.  **Tag:** Create a new tag (e.g., `v2.4.3`).
2.  **Release:** Create a GitHub Release for that tag.
3.  **Major Alias:** Manually update the `v2` major tag to point to the new release.
    ```bash
    git tag -f v2 v2.4.3
    git push origin v2 --force
    ```
    *This ensures users pinned to `@v2` automatically get the update.*
