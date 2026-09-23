# Contract: Hardening Checklist & Gate

**Feature**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23

## Artifact

`specs/002-hardened-bootc-pipeline/checklists/hardening.md` — the checklist itself.
**This contract defines how items are declared and how their outcomes gate the
pipeline.**

## Item schema

Each item is a markdown block matching this layout exactly:

```
### H0NN <title>

- **Pillar**: build | runtime | updates
- **Automatable**: yes | no
- **Check** (automatable): `<shell command / script reference>`
- **Evidence**: <what demonstrates pass>
- **Owner** (manual-verify): <name>
- **Failure policy**: fail-closed
```

Automatable items MUST have a `Check` that is executable against either (a) the
built image in a throwaway podman container (phase `image`), or (b) the smoke-booted
VM over ssh (phase `runtime`). Manual-verify items MUST have an `Owner`.

## Engine semantics (`scripts/hardening-verify.sh`)

- Two phases per pipeline run: `image` (static, on built image) and `runtime`
  (live, on smoke VM over ssh). Item declares its phase implicitly by its check.
- Every automatable item MUST return exit 0 (PASS) or non-zero (FAIL). There is no
  WARN. There is no SKIP with a positive interpretation. A missing/unparseable
  item is treated as FAIL.
- Engine exits non-zero if ≥1 item fails. Pipeline aborts at `validate` stage
  (exit 4) before any registry push or VM release.
- Engine emits the verdict matrix to the execution record (see
  `contracts/execution-record.md`), one row per item: `item_id | phase | PASS|FAIL |
  raw-evidence-fixture`.

## Baseline admitted listener set

The checklist's H014 comparison set for "no listeners beyond enumerated" is versioned
inside the checklist file itself:

| Listener | Justification |
|----------|---------------|
| tcp/22 (sshd) | pre-authorized baseline (Q1 clarification) |

Any change to this set requires a checklist-file commit bump (constitution —
governance change).

## Manual-verify items

Currently declared (v1):

- **H040** VM-level disk encryption decision (documented exception — host LUKS
  rationale per spec Assumptions) — owner: chris
- **H041** Secure Boot inside guest — manual verification (bib UEFI support
  matrix at release time) — owner: chris

Additions/changes to manual items are checklist-file commits reviewed like any
other constitution-adjacent artifact.
