# Driver validation evidence

These directories store **point-in-time proof** from native macOS dogfood runs.
`manifest.json` and cache files may reference absolute paths on the maintainer
machine (`/Users/...`, internal monorepo checkouts). They are not secrets, but
they are not portable paths — treat them as provenance metadata, not install
instructions.

For current validation commands, see the package README and
[`CONTRIBUTING.md`](../../../CONTRIBUTING.md) at the repo root.
