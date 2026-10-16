# Vision and principles

**Audience:** humans and agents · **Status:** orientation (not a substitute for
ADRs or proof)

This document compresses **directions already stated** in this repository and in
sibling stewardship repos. It does not add new product commitments.

## Optimistic direction

We want a future where **people and AI agents can understand and work with real
devices and apps** through the same honest, composable automation surface —
desktop, mobile, browser, and tiers the family adds over time — instead of opaque
one-off scripts per platform.

That surface is built from:

- Shared **contracts** (`universal_automation_*`) and **drivers** that implement them
- **Declarative, compositional** plans (typed Dart with YAML snapshots for agents)
- **Observe / act / verify** loops with receipts, aligned with the wider
  automation chain described in [`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter)

Innovation here is **legible automation**: smaller, inspectable routes for the
next human or agent, not bigger black boxes.

## Care and ethics (grounded in repo sources)

| Principle | Where it comes from | What it means here |
| --- | --- | --- |
| **Consent and least privilege** | [SECURITY.md](../SECURITY.md), toolkit consent-gated drivers | Prefer `ConsentGatedDriver` / OS permission flows before accessibility or screen-recording effects; run only on machines and apps you control. |
| **Privileged surface, fail-closed plans** | [SECURITY.md](../SECURITY.md), toolkit README | Treat MCP/CLI like a developer agent capability; plans and drivers should **refuse loudly** when a tier or permission is missing rather than guessing. |
| **Honest claims and evidence** | [AGENTS.md](../AGENTS.md), [steward.yaml](../steward.yaml) | Name the exact claim, prove the weakest bar, record non-claims; `stewardship.quality.validate` and ADRs gate durable changes. |
| **Action effects and provenance** | [steward.yaml](../steward.yaml) (`security.action_effects`, `release.artifact_provenance`) | Automation that can change the world needs explicit effect metadata and traceable artifacts where the contract requires it. |
| **Community conduct** | [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Contributor Covenant; report security issues privately per SECURITY.md. |
| **Engineering stewardship** | [Skill Steward NORTH_STAR](https://github.com/Arenukvern/skill_steward/blob/main/docs/NORTH_STAR.mdx), [CONTRIBUTING.md](../CONTRIBUTING.md) | Charter, docs, validation gates, and handoff patterns so agents and humans share the same map — adopted from the mcp_flutter / skill_steward OSS pattern. |

Broader ethical framing for the author’s work (not specific to this repo’s code)
is summarized in the public
[Principles at work (credo)](https://dev.to/arenukvern/my-principles-at-work-credo-182c)
linked from Skill Steward’s north star.

## North star impact habit

Structural changes should be classified (`north_star_impact`: `none`, `applies`,
`clarifies`, `sub_star`, `amends`, `conflicts`) before a mechanism becomes the
mission. See [AGENTS.md](../AGENTS.md).

## What we do not claim

- Production-ready automation on every OS tier without platform-specific proof
- Replacement for app-centric harnesses ([`mcp_flutter`](https://github.com/Arenukvern/mcp_flutter)
  remains the Flutter runtime story)
- That agents may operate user devices without explicit consent and security review

Durable decisions live in [docs/decisions/](decisions/).

---

<sup>*</sup> *Quiet aside:* contracts are written for whoever needs legible
device access next — today humans and agents; tomorrow maybe someone with fins,
a star chart, or a handshake we have not imagined yet. That is curiosity, not a
roadmap; see the banner horizon if you like scavenger hunts.
