#!/usr/bin/env bash
# Integration tests for assert_release_git_tag_at_sha.sh (file:// remote).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/tool/release/assert_release_git_tag_at_sha.sh"

fail() { echo "test_assert_release_git_tag_at_sha: $*" >&2; exit 1; }
ok() { echo "test_assert_release_git_tag_at_sha: $*"; }

assert_pass() {
  local tag="$1" sha="$2" remote="$3"
  GITHUB_REPOSITORY=local/test RELEASE_GIT_REMOTE="$remote" RELEASE_SHA="$sha" \
    bash "$SCRIPT" "$tag" || fail "expected pass: tag=$tag sha=$sha"
  ok "pass tag=$tag"
}

assert_fail_contains() {
  local want="$1"
  shift
  local tag="$1" sha="$2" remote="$3"
  local out
  set +e
  out="$(GITHUB_REPOSITORY=local/test RELEASE_GIT_REMOTE="$remote" RELEASE_SHA="$sha" \
    bash "$SCRIPT" "$tag" 2>&1)"
  local st=$?
  set -e
  [[ "$st" -ne 0 ]] || fail "expected failure: tag=$tag ($want)"
  [[ "$out" == *"$want"* ]] || fail "stderr must contain '$want' (got: $out)"
  ok "fail tag=$tag ($want)"
}

commit_file() {
  local repo="$1" msg="$2"
  local f="$repo/dummy.txt"
  echo "$msg" >>"$f"
  git -C "$repo" add dummy.txt
  git -C "$repo" -c user.email=t@test -c user.name=t commit -q -m "$msg"
  git -C "$repo" rev-parse 'HEAD^{commit}'
}

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

bare="$tmpdir/remote.git"
work="$tmpdir/work"
git init --bare -q "$bare"
git clone -q "$bare" "$work"
git -C "$work" checkout -q -b main 2>/dev/null || git -C "$work" branch -M main
sha_a="$(commit_file "$work" "commit-a")"
git -C "$work" tag universal_automation_toolkit-v0.1.0
git -C "$work" push -q -u origin main --tags

sha_b="$(commit_file "$work" "commit-b")"
git -C "$work" tag -a universal_automation_toolkit-v0.2.0 -m "annotated"
git -C "$work" push -q origin main --tags
sha_b_commit="$(git -C "$work" rev-parse 'HEAD^{commit}')"
# shellcheck disable=SC2034
_unused="$sha_b"

remote="file://$bare"

assert_pass universal_automation_toolkit-v0.1.0 "$sha_a" "$remote"
assert_fail_contains "!= expected release SHA" universal_automation_toolkit-v0.1.0 "0000000000000000000000000000000000000000" "$remote"

assert_pass universal_automation_toolkit-v0.2.0 "$sha_b_commit" "$remote"
assert_fail_contains "!= expected release SHA" universal_automation_toolkit-v0.2.0 "$sha_a" "$remote"

assert_fail_contains "not found" universal_automation_toolkit-v0.9.9 "$sha_a" "$remote"

bad_remote="file://$tmpdir/does-not-exist.git"
set +e
out="$(GITHUB_REPOSITORY=local/test RELEASE_GIT_REMOTE="$bad_remote" RELEASE_SHA="$sha_a" \
  bash "$SCRIPT" universal_automation_toolkit-v0.1.0 2>&1)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "unreachable remote must fail"
[[ "$out" == *"git ls-remote failed"* ]] || fail "must report ls-remote failure (got: $out)"
ok "unreachable remote rejected"

ok "all assert_release_git_tag_at_sha integration tests passed"