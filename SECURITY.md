# Security Policy

Computer-use automation can observe and act on the local OS, browsers, and
apps. Treat this toolkit like a privileged developer agent surface.

See also [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community expectations.

## Reporting A Vulnerability

Report privately to anton@xsoulspace.dev. Include affected package, steps,
impact, and whether the issue is already public. Do not open a public issue
for an unpatched vulnerability.

## Local Safety Notes

- Run only against machines, browsers, and apps you control.
- Prefer consent-gated drivers (`xsoulspace_permission_core`) before
  accessibility or screen-recording effects.
- Keep MCP/CLI serve surfaces bound to trusted local clients.
