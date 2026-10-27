# Computer-use parity evidence (2026-10-27)

Plumbing gate (TextEdit, Cursor may stay frontmost):

```bash
cd pkgs/universal_automation_toolkit
dart run example/computer_use_parity_probe.dart docs/evidence/computer-use-parity-2026-10-27
```

Product arc (pub.dev GitHub Actions admin, Chrome without CDP):

```bash
dart run pkgs/universal_automation_toolkit/example/pubdev_computer_use_evidence.dart \
  docs/evidence/computer-use-parity-2026-10-27/pubdev
```

Commit `pubdev/evidence.json` + PNGs. Form completion still needs a logged-in
Chrome + agent vision; UA supplies bind/screenshot/click in image space.
