#!/usr/bin/env python3
"""Regenerate release workflow negative fixtures from golden workflows (single violation each)."""
from __future__ import annotations

import copy
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOLDEN = {
    "build": ROOT / ".github/workflows/release_binaries_build.yml",
    "publish": ROOT / ".github/workflows/release_binaries_publish.yml",
    "dispatch": ROOT / ".github/workflows/release_binaries.yml",
    "pr": ROOT / ".github/workflows/release_binaries_pr.yml",
    "please": ROOT / ".github/workflows/release-please.yml",
}

OUT = {
    "build": ROOT / "tool/contracts/fixtures/release_workflow",
    "publish": ROOT / "tool/contracts/fixtures/release_workflow_publish",
    "dispatch": ROOT / "tool/contracts/fixtures/release_workflow_dispatch",
    "pr": ROOT / "tool/contracts/fixtures/release_workflow_pr",
    "please": ROOT / "tool/contracts/fixtures/release_workflow_please",
}

VALIDATOR = {
    "build": "build",
    "publish": "publish",
    "dispatch": "dispatch",
    "pr": "pr",
    "please": "please",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_fixture(kind: str, name: str, text: str) -> None:
    out_dir = OUT[kind]
    out_dir.mkdir(parents=True, exist_ok=True)
    yml = out_dir / f"{name}.yml"
    yml.write_text(text, encoding="utf-8")


def dart_errors(kind: str, yml: Path) -> str:
    if kind == "pr":
        cmd = ["dart", "run", str(ROOT / "tool/check_release_workflow.dart"), "--pr-smoke-workflow", str(yml)]
    elif kind == "please":
        cmd = [
            "dart",
            "run",
            str(ROOT / "tool/check_release_workflow.dart"),
            "--please-caller-workflow",
            str(yml),
        ]
    else:
        cmd = ["dart", "run", str(ROOT / "tool/check_release_workflow.dart"), "--workflow", str(yml)]
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return (p.stdout + p.stderr).strip()


def pick_error_substring(output: str) -> str:
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("- "):
            return line[2:].split(" (got ")[0]
    if "failures:" in output:
        return output.split("failures:")[-1].strip().splitlines()[-1].strip()
    return output.splitlines()[-1] if output else "must fail"


def record(kind: str, name: str, text: str) -> None:
    write_fixture(kind, name, text)
    yml = OUT[kind] / f"{name}.yml"
    out = dart_errors(kind, yml)
    sub = pick_error_substring(out)
    exp = OUT[kind] / f"{name}.yml.expected"
    exp.write_text(sub + "\n", encoding="utf-8")
    if "OK" in out or not sub:
        raise SystemExit(f"{name}: expected failure, got: {out}")


def b() -> str:
    return read_text(GOLDEN["build"])


def p() -> str:
    return read_text(GOLDEN["publish"])


def d() -> str:
    return read_text(GOLDEN["dispatch"])


def pr() -> str:
    return read_text(GOLDEN["pr"])


def pl() -> str:
    return read_text(GOLDEN["please"])


def main() -> None:
  specs = []

  # --- build ---
  t = b()
  specs.append(("build", "negative_no_workflow_call", re.sub(r"\n  workflow_call:\n.*?(?=\npermissions:)", "\n", t, count=1, flags=re.S)))
  specs.append((
      "build",
      "negative_push",
      re.sub(
          r"^on:\n  workflow_call:",
          "on:\n  push:\n    branches: [main]\n  workflow_call:",
          t,
          count=1,
          flags=re.M,
      ),
  ))

  t = b()
  specs.append((
      "build",
      "negative_matrix_fifth_platform",
      t.replace(
          "          - triple: windows-x64\n            runner: windows-latest",
          "          - triple: windows-x64\n            runner: windows-latest\n"
          "          - triple: linux-arm64\n            runner: ubuntu-latest",
          1,
      ),
  ))

  specs.append((
      "build",
      "negative_contents_write_prepare",
      t.replace("  prepare:\n    runs-on:", "  prepare:\n    permissions:\n      contents: write\n    runs-on:", 1),
  ))

  specs.append((
      "build",
      "negative_continue_on_error",
      t.replace("  build:\n    needs:", "  build:\n    continue-on-error: true\n    needs:", 1),
  ))

  specs.append((
      "build",
      "negative_run_name_wrong",
      t.replace(
          "release-binaries-build ${{ inputs.dry_run == true && 'dry-run' || inputs.release_tag }}",
          "release-binaries-build WRONG",
          1,
      ),
  ))

  specs.append((
      "build",
      "negative_secrets_build_env",
      t.replace(
          "      HAS_CERT_PASSWORD:",
          "      LEAK_CERT: ${{ secrets.MACOS_CERT_P12 }}\n      HAS_CERT_PASSWORD:",
          1,
      ),
  ))

  specs.append((
      "build",
      "negative_secrets_step_if",
      t.replace(
          "      - name: Warn partial macOS signing secrets",
          "      - name: Evil step if\n        if: secrets.MACOS_CERT_P12 != ''\n        run: echo bad\n\n      - name: Warn partial macOS signing secrets",
          1,
      ),
  ))

  specs.append((
      "build",
      "negative_secrets_in_with",
      t.replace(
          "          name: release-${{ matrix.triple }}",
          "          name: release-${{ matrix.triple }}\n          token: ${{ secrets.EVIL_TOKEN }}",
          1,
      ),
  ))

  specs.append((
      "build",
      "negative_set_plus_e_before_verify",
      t.replace(
          "          bash \"${{ env.TOOLING_CHECKOUT_PATH }}/tool/release/verify_release_tarball_architecture.sh\"",
          "          set +e\n          bash \"${{ env.TOOLING_CHECKOUT_PATH }}/tool/release/verify_release_tarball_architecture.sh\"",
          1,
      ),
  ))

  specs.append((
      "build",
      "negative_if_always_prefix",
      t.replace("    if: inputs.dry_run == true", "    if: always() || inputs.dry_run == true", 1),
  ))

  specs.append((
      "build",
      "negative_if_github_event",
      t.replace("    if: inputs.dry_run == true", "    if: github.event.inputs.dry_run == 'true'", 1),
  ))

  specs.append((
      "build",
      "negative_build_contains_publish",
      t + "\n  publish:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo bad\n",
  ))
  specs.append((
      "build",
      "negative_workflow_contents_write",
      t.replace("permissions:\n  contents: read", "permissions:\n  contents: write", 1),
  ))

  specs.append((
      "build",
      "negative_build_wrong_needs",
      t.replace("  build:\n    needs: prepare", "  build:\n    needs: []", 1),
  ))

  # --- publish ---
  t = p()
  specs.append(("publish", "negative_fail_on_unmatched_false", t.replace("fail_on_unmatched_files: true", "fail_on_unmatched_files: false", 1)))
  specs.append((
      "publish",
      "negative_assert_if_false",
      t.replace(
          "      - name: Assert release has all assets and checksums",
          "      - name: Assert release has all assets and checksums\n        if: false",
          1,
      ),
  ))
  specs.append((
      "publish",
      "negative_assert_reference",
      t.replace(
          '          bash "${{ env.TOOLING_CHECKOUT_PATH }}/tool/release/assert_release_assets_complete.sh"',
          "          # assert_release_assets_complete.sh referenced in comment only",
          1,
      ),
  ))
  specs.append((
      "publish",
      "negative_conflict_guard_if",
      t.replace(
          "      - name: Guard against conflicting GitHub release assets",
          "      - name: Guard against conflicting GitHub release assets\n        if: false",
          1,
      ),
  ))
  specs.append(("publish", "negative_postflight_renamed", t.replace("  postflight:", "  postflight_check:", 1)))
  specs.append(("publish", "negative_publish_needs_postflight", t.replace("  publish:\n    permissions:", "  publish:\n    needs: [postflight]\n    permissions:", 1)))
  specs.append((
      "publish",
      "negative_exit0_before_assert",
      t.replace(
          '          bash "${{ env.TOOLING_CHECKOUT_PATH }}/tool/release/assert_release_assets_complete.sh"',
          "          exit 0\n          bash \"${{ env.TOOLING_CHECKOUT_PATH }}/tool/release/assert_release_assets_complete.sh\"",
          1,
      ),
  ))
  specs.append((
      "publish",
      "negative_true_comment_assert",
      re.sub(
          r'        run: \|\n'
          r'          bash "\$\{\{ env\.TOOLING_CHECKOUT_PATH \}\}/tool/release/assert_release_assets_complete\.sh" \\\n'
          r'            "\$RELEASE_TAG" \\\n'
          r'            "\$VERSION"',
          '        run: echo postflight skipped',
          t,
          count=1,
      ),
  ))
  specs.append((
      "publish",
      "negative_publish_cross_run_download",
      t.replace(
          "      - name: Download release artifacts from this workflow run\n        uses: actions/download-artifact@v4\n        with:\n          path: dist/release",
          "      - name: Download release artifacts from this workflow run\n        uses: actions/download-artifact@v4\n        with:\n          github-token: ${{ github.token }}\n          run-id: '99999'\n          path: dist/release",
          1,
      ),
  ))
  specs.append((
      "publish",
      "negative_gh_release_missing_asset",
      t.replace(
          "            dist/release/universal_automation_${{ inputs.version }}_windows-x64.zip\n",
          "",
          1,
      ),
  ))
  specs.append((
      "publish",
      "negative_publish_no_download",
      re.sub(
          r"      - name: Download release artifacts from this workflow run\n.*?\n\n",
          "",
          t,
          count=1,
          flags=re.S,
      ),
  ))

  # --- dispatch ---
  t = d()
  specs.append((
      "dispatch",
      "negative_dispatch_extra_publish_job",
      t.replace(
          "jobs:\n  build:",
          "jobs:\n  extra-publish:\n    uses: ./.github/workflows/release_binaries_publish.yml\n  build:",
          1,
      ),
  ))

  specs.append((
      "dispatch",
      "negative_secrets_inherit",
      t.replace(
          "    secrets:\n"
          "      MACOS_CERT_P12: ${{ secrets.MACOS_CERT_P12 }}\n"
          "      MACOS_CERT_PASSWORD: ${{ secrets.MACOS_CERT_PASSWORD }}\n"
          "      MACOS_CODESIGN_IDENTITY: ${{ secrets.MACOS_CODESIGN_IDENTITY }}\n"
          "      APPLE_ID: ${{ secrets.APPLE_ID }}\n"
          "      APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}\n"
          "      APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}",
          "    secrets: inherit",
          1,
      ),
  ))

  # --- pr ---
  t = pr()
  specs.append(("pr", "negative_pr_dry_run_false", t.replace("dry_run: true", "dry_run: false", 1)))
  specs.append((
      "pr",
      "negative_pr_wrong_workflow",
      t.replace("release_binaries_build.yml", "release_binaries.yml", 1),
  ))
  specs.append((
      "pr",
      "negative_pr_secrets",
      t.replace(
          "    with:\n",
          "    secrets:\n      MACOS_CERT_P12: ${{ secrets.MACOS_CERT_P12 }}\n    with:\n",
          1,
      ),
  ))
  specs.append((
      "pr",
      "negative_pr_secrets_inherit",
      t.replace(
          "    with:\n",
          "    secrets: inherit\n    with:\n",
          1,
      ),
  ))

  # --- release-please ---
  t = pl()
  specs.append((
      "please",
      "negative_please_secrets_inherit",
      re.sub(
          r"(release-binaries-build:[\s\S]*?uses: \./\.github/workflows/release_binaries_build\.yml\n)    secrets:\n(?:      \w+:.*\n){6}",
          r"\1    secrets: inherit\n",
          t,
          count=1,
      ),
  ))
  specs.append((
      "please",
      "negative_please_wrong_build_workflow",
      t.replace(
          "    uses: ./.github/workflows/release_binaries_build.yml",
          "    uses: ./.github/workflows/release_binaries.yml",
          1,
      ),
  ))
  specs.append((
      "please",
      "negative_please_build_contents_write",
      re.sub(
          r'(release-binaries-build:[\s\S]*?permissions:\n      )contents: read',
          r'\1contents: write',
          t,
          count=1,
      ),
  ))
  specs.append((
      "publish",
      "negative_publish_contents_write_postflight",
      p().replace(
          "  postflight:\n    permissions:\n      contents: read",
          "  postflight:\n    permissions:\n      contents: write",
          1,
      ),
  ))

  specs.append((
      "please",
      "negative_please_audit_skips_on_wait_failure",
      re.sub(
          r"\(\n\s+needs\.wait-package-publish\.result == 'success' \|\|\n"
          r"\s+needs\.wait-package-publish\.result == 'failure'\n\s+\)",
          "needs.wait-package-publish.result == 'success'",
          t,
          count=1,
      ),
  ))

  specs.append((
      "please",
      "negative_please_wait_blocks_on_binaries",
      t.replace(
          "      needs.dispatch-package-publish.result == 'success'",
          "      needs.dispatch-package-publish.result == 'success' &&\n"
          "      (needs.release-binaries-build.result == 'success' || needs.release-binaries-build.result == 'skipped')",
          1,
      ).replace(
          "    needs:\n      - release-please\n      - dispatch-package-publish",
          "    needs:\n      - release-please\n      - dispatch-package-publish\n"
          "      - release-binaries-build",
          1,
      ),
  ))

  for kind, name, text in specs:
    record(kind, name, text)
    print(f"OK {kind}/{name}")

  print(f"generated {len(specs)} negative fixtures")


if __name__ == "__main__":
    main()