#!/usr/bin/env bash
# Integration tests for assert_release_git_tag_at_sha.sh (file:// remote).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/tool/release/assert_release_git_tag_at_sha.sh"

fail() { echo "test_assert_release_git_tag_at_sha: $*" >&2; exit 1; }
ok() { echo "test_assert_release_git_tag_at_sha: $*"; }

GIT_IDENTITY=( -c user.name=ci -c user.email=ci@example.invalid )

if grep -qE 'x-access-token:\$\{GH_TOKEN\}@' "$SCRIPT" \
  || grep -qE 'x-access-token:\$GH_TOKEN@' "$SCRIPT"; then
  fail "script must not embed GH_TOKEN in remote URL"
fi
ok "script has no token-in-URL pattern"

empty_home="$(mktemp -d)"
export HOME="$empty_home"
export GIT_AUTHOR_NAME=ci
export GIT_AUTHOR_EMAIL=ci@example.invalid
export GIT_COMMITTER_NAME=ci
export GIT_COMMITTER_EMAIL=ci@example.invalid

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
  git -C "$repo" "${GIT_IDENTITY[@]}" commit -q -m "$msg"
  git -C "$repo" rev-parse 'HEAD^{commit}'
}

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir" "$empty_home"; }
trap cleanup EXIT

bare="$tmpdir/remote.git"
work="$tmpdir/work"
git init --bare -q "$bare"
git -c init.defaultBranch=main clone -q "$bare" "$work"
git -C "$work" checkout -q -b main 2>/dev/null || git -C "$work" branch -M main
sha_a="$(commit_file "$work" "commit-a")"
git -C "$work" "${GIT_IDENTITY[@]}" tag universal_automation_toolkit-v0.1.0
git -C "$work" push -q -u origin main --tags

sha_b="$(commit_file "$work" "commit-b")"
git -C "$work" "${GIT_IDENTITY[@]}" tag -a universal_automation_toolkit-v0.2.0 -m "annotated"
git -C "$work" push -q origin main --tags
sha_b_commit="$(git -C "$work" rev-parse 'HEAD^{commit}')"

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

fake_token="ghs_TESTTOKEN123"
set +e
out="$(
  HOME="$empty_home" GH_TOKEN="$fake_token" \
    GITHUB_REPOSITORY='ci-example/nonexistent-repo-for-ls-remote-test' \
    RELEASE_SHA=0000000000000000000000000000000000000000 \
    bash "$SCRIPT" universal_automation_toolkit-v0.1.0 2>&1
)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "github ls-remote failure must exit non-zero"
[[ "$out" == *"git ls-remote failed"* ]] || fail "must report ls-remote failure (got: $out)"
[[ "$out" != *"$fake_token"* ]] || fail "error output must not contain GH_TOKEN"
ok "github ls-remote errors omit token"

ok "all assert_release_git_tag_at_sha integration tests passed"