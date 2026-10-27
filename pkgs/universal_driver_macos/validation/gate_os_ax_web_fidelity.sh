#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
dart test pkgs/universal_driver_macos/test/macos_driver_test.dart \
  --plain-name "window-local"
dart test pkgs/universal_automation_toolkit/test/mcp_server_test.dart \
  --plain-name "automation_preview"
echo "gate_os_ax_web_fidelity: ok"
