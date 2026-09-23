# Implementation Plan: Capture Current System State

**Branch**: `001-capture-system-state` (spec) / working tree on `main` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-capture-system-state/spec.md`

## Summary

Deliver a checked-in, idempotent capture driver — `scripts/capture-state.sh` — that performs a
strictly read-only, unprivileged observation pass over SSH against `chris@donnager-linux`,
normalizes results into a Markdown **Main Report** plus a **Packages Appendix** under `state/`,
and supports the reviewer (agent or human) with structured scaffolding for the per-domain
Findings sections. The repository's `.gitignore` is updated first as a hard precondition
(FR-012a). No implementation-time SSH occurs during `/speckit.plan`; the capture run is the
implementation phase (`/speckit.tasks` / implement).

## Technical Context

**Language/Version**: Bash 5+ (capture driver `scripts/capture-state.sh`); Markdown artifacts.

**Primary Dependencies**:
- Local (driver host): `ssh` with BatchMode, coreutils (`date`, `mktemp`), `git` (for
  `check-ignore` precondition).
- Remote (`donnager-linux`, read-only, unprivileged): `rpm`, `systemctl` (system + `--user`),
  `ip`, `ss`, `resolvectl`, `findmnt`, `lsblk`, `lscpu`, `uname`, `getenforce`,
  `bootctl` (best-effort, may be gated), `mokutil` (best-effort, may be gated),
  `podman`/`docker` (if present), `virsh` (user session only), `nvidia-smi`
  (if present). Every remote command is in a fixed, audited allowlist in the script.

**Storage**: Local filesystem only — `state/` (git-ignored). No database.

**Testing**:
- `bash -n scripts/capture-state.sh` and `shellcheck` for lint sanity.
- `git check-ignore -v state/…` to validate the FR-012a precondition.
- Manual acceptance per `quickstart.md` (SC-001…SC-006).

**Target Platform**: driver runs on macOS/Linux workstation; target is Fedora Linux
(remote, x86_64, RPM-based, systemd).

**Project Type**: tooling / runbook feature (not a service, not a library).

**Performance Goals**: one capture run completes in ≤ 5 minutes wall-clock on a healthy
SSH link; total remote invocations ≤ ~80.

**Constraints**:
- Strictly read-only on the target; **no sudo, no privilege escalation** (Clarification Q1).
- **No writes on the remote filesystem**; everything streamed back over SSH stdout.
  (Strengthens FR-002; even `/tmp` writes on target are avoided as unnecessary.)
- Fixed, allowlisted command inventory in the script — no ad-hoc shell.
- `.gitignore` excludes `state/` **before** any artifact is written.
- No new credentials, keys, or secrets material introduced anywhere.
- No changes to this repository outside `scripts/`, `state/`, and `.gitignore`.

**Scale/Scope**: single host; ~40–80 remote observational invocations; 2 output artifacts
(main report + packages appendix); 6 domain sections (host context, packages, network,
containers, services, VMs) + repo-artifacts cross-reference + provenance.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Verdict | Evidence |
|-----------|------|---------|----------|
| I. Automation-First, Drift-Resistant | Capture must be automatable and reproducible, not one-off typing. | PASS | The capture is embodied as a checked-in script (`scripts/capture-state.sh`) run via SSH; every command is in the script and therefore auditable. |
| II. Image-Based System Definition (bootc) | Base OS definition changes go through the Containerfile. | N/A | This feature does not define or mutate the OS image. |
| III. Security as a Non-Negotiable | No privilege escalation, no secrets in repo, least privilege, secrets never committed. | PASS | No sudo (Q1), no remote writes, no new credentials, artifacts land in git-ignored `state/` only, FR-012a precondition enforced. |
| IV. State Capture Before Change | State captured in-repo before transformation. | PASS | This feature *is* the state-capture mechanism; report lives under `state/` and is discoverable from repo root. |
| V. Dual-Purpose Awareness (Lab + Desktop) | Both roles represented. | PASS | FR-008 requires GPU, virt extensions, IOMMU, Secure Boot host context; FR-007 covers libvirt. |

Re-check after Phase 1 design (below): **still PASS** — the design introduces no violations
(`research.md`, `data-model.md`, `contracts/`, `quickstart.md` add automation, prov-enforced
secrecy of `state/`, and reproducibility).

## Project Structure

### Documentation (this feature)

```text
specs/001-capture-system-state/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── capture-cli.md   # Script interface contract
│   └── state-report.md  # Report markdown structure contract
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
scripts/
└── capture-state.sh           # NEW — checked-in capture driver (executable, bash)

state/                          # NEW — generated at run time; EXCLUDED by .gitignore
├── donnager-linux-YYYYMMDD.md          # Main Report
└── donnager-linux-YYYYMMDD-packages.md # Packages Appendix

.gitignore                      # MODIFIED — add `state/` exclusion (FR-012a precondition)
```

**Structure Decision**: single-project layout (this repository is a system-management repo, not
a service). The capture driver lives under existing `scripts/` to stay close to other host
automation (`scripts/granite-20.sh`). Generated artifacts are confined to a new git-ignored
`state/` directory. No new languages, frameworks, or package managers are introduced.

## Complexity Tracking

No constitution violations; no entries required.
