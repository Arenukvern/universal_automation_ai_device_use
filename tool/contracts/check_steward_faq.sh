#!/usr/bin/env bash
# Steward docs contract: North Star + paired FAQs, symlinks, steward.yaml registration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "check_steward_faq: $*" >&2
  exit 1
}

[[ -f docs/NORTH_STAR.mdx ]] || fail 'missing docs/NORTH_STAR.mdx'
grep -q 'north_star: docs/NORTH_STAR.mdx' steward.yaml ||
  fail 'steward.yaml missing stewardship.governance.north_star'
grep -q 'vision_source: docs/NORTH_STAR.mdx' steward.yaml ||
  fail 'steward.yaml missing stewardship.strategic_alignment.vision_source'

grep -q 'North Star' docs.json ||
  fail 'docs.json sidebar should list North Star'
grep -q '**Status:**' docs/NORTH_STAR.mdx ||
  fail 'NORTH_STAR.mdx should include **Status:** front line (skill_steward pattern)'

[[ -f docs/DESIGN_FAQ.mdx ]] || fail 'missing docs/DESIGN_FAQ.mdx'
[[ -f docs/DX_FAQ.mdx ]] || fail 'missing docs/DX_FAQ.mdx'

grep -q 'design: docs/DESIGN_FAQ.mdx' steward.yaml ||
  fail 'steward.yaml missing stewardship.governance.faq.design'
grep -q 'dx: docs/DX_FAQ.mdx' steward.yaml ||
  fail 'steward.yaml missing stewardship.governance.faq.dx'

if grep -q '^## North Star' docs/DESIGN_FAQ.mdx; then
  fail 'DESIGN_FAQ.mdx must not duplicate a North Star section; link /NORTH_STAR instead'
fi

for link in DESIGN_FAQ.md DX_FAQ.md; do
  [[ -L "$link" ]] || fail "missing root symlink $link"
  target="$(readlink "$link")"
  [[ "$target" == "docs/${link%.md}.mdx" ]] ||
    fail "$link should symlink to docs/${link%.md}.mdx (got $target)"
done

grep -q '\*\*Q:' docs/DESIGN_FAQ.mdx ||
  fail 'DESIGN_FAQ.mdx should use **Q:** entries'
grep -q '\*\*Q:' docs/DX_FAQ.mdx ||
  fail 'DX_FAQ.mdx should use **Q:** entries'

grep -q 'Design FAQ' docs.json ||
  fail 'docs.json sidebar should list Design FAQ'
grep -q 'DX FAQ' docs.json ||
  fail 'docs.json sidebar should list DX FAQ'

echo 'check_steward_faq: OK'