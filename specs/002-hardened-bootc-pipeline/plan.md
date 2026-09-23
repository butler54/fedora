# Implementation Plan: Hardened Fedora 44 bootc VM Pipeline

**Branch**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-hardened-bootc-pipeline/spec.md`

## Summary

Deliver a repo-defined, local-first pipeline — entry point `make pipeline` — that builds a
hardened Fedora 44 bootc OCI image from a digest-pinned base, scans and gates it with a
hardening checklist (fail-closed), pushes it to a private OCI registry, materializes a
QCOW2 via `bootc-image-builder` on the lab host, and starts a user-session libvirt VM
consuming that volume. Two committed analysis documents (tempest-concorde patterns,
prioritized security recommendations) are produced as part of delivery. All pipeline
execution records land in the git-ignored `state/` directory per feature-001 conventions.

Execution model follows feature 001: the authoring machine drives `donnager-linux` over
BatchMode SSH; no new host packages, firewall, or service changes are introduced (FR-009).
`bootc-image-builder` runs as a container on the lab host (the only host-visible effects
are podman containers/images and VM volume files under the lab user's home).

## Technical Context

**Language/Version**: Bash ≥ 5 (pipeline + checklist engine); Containerfile (OCI); TOML
(bootc-image-builder config, gomplate-templated per tempest-concorde pattern); Make
(entry-point façade only — logic lives in `scripts/`).

**Primary Dependencies**:
- Authoring host: `ssh` (BatchMode), `make`, `git`, `gomplate` (config templating).
- Lab host (`donnager-linux`, already verified): `podman 5.8`, `virsh`/`virt-install`
  (user session), `qemu-img`, `curl`, `gh` (optional for future CI). No new host packages.
- Build time (containerized on lab host): `quay.io/centos-bootc/bootc-image-builder`
  (digest-pinned), base `quay.io/fedora/fedora-bootc:44` (digest-pinned).
- VM: Fedora 44 bootc deployment referencing the pushed registry image; `bootc upgrade`
  timer for updates.

**Storage**: OCI registry (default private `quay.io` repo; parameter `REGISTRY_REF`);
QCOW2 volumes under the lab user's libvirt user-session pool (`~/.local/share/libvirt/images`
or a documented pool); execution records under repo `state/` (git-ignored).

**Testing**: `bash -n` + shellcheck on scripts; checklist engine self-test against a
deliberately-broken fixture image (proves fail-closed); end-to-end acceptance per
`quickstart.md`; SC-007 zero-host-regression check via feature-001 capture diff.

**Target Platform**: Linux lab host (Fedora 44, x86_64, KVM enabled — verified);
pipeline authoring on any ssh-capable host.

**Project Type**: infrastructure/automation feature (image + pipeline + docs). Not a
service, not a library.

**Performance Goals**: full pipeline ≤ 30 min wall time on lab hardware (SC-001);
VM to login prompt ≤ 2 min (SC-002).

**Constraints**:
- No host mutations beyond: podman containers/images, VM volumes + domains in user-session
  libvirt, files under the lab user's home. Nothing else (FR-009).
- Digest-pinned base and builder images; every external artifact reference recorded with
  its digest in the run's execution record.
- No secrets in repo or image; registry auth via host environment at pipeline time;
  VM pull secret provisioned via cloud-init data at VM creation time only.
- Registry push and checklist pass are both fail-closed release gates before VM acceptance.
- Pipeline parameterizes (host, registry ref, VM name, resources, network profile) but
  defaults must produce the hardened VM with zero extra flags.
- Package efficiency (user directive): Containerfile declares dnf **groups (bundles)**,
  not individual packages, wherever a group exists; duplicate
  package-in-declared-group is a hard pipeline error; group expansion evidence is
  recorded per build.
- GPU/NVIDIA (user directive): VM image carries **no NVIDIA components** (GPU/VFIO
  out of scope); NVIDIA best-practice analysis (R580+ open-modules lane, rpmfusion
  kernel modules vs CUDA-repo userland split, CDI for containers) lands in
  `docs/security-recommendations.md`.

**Scale/Scope**: 1 pipeline entry point, ~6 pipeline stages, ~15–25 hardening checklist
items, 1 default VM (4 vCPU / 8 GiB / 60 GiB), 2 committed analysis documents, 1 updated
`bootc/Containerfile`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence |
|-----------|---------|----------|
| I. Automation-First | PASS | Everything repo-defined; single `make pipeline` entry; execution records auto-written |
| II. Image-Based System Definition | PASS | Feature is the mechanism that strengthens P.II; OS defined in `bootc/Containerfile` |
| III. Security Non-Negotiable | PASS | Digest pinning, fail-closed checklist, no secrets in repo/image, key-only sshd, SELinux Enforcing, registry-auth hygiene; See Security Requirements section of constitution — all inherited |
| IV. State Capture Before Change | PASS | Feature 001 satisfied the pre-condition; this feature's execution records extend the same `state/` convention |
| V. Dual-Purpose Awareness | PASS | Default NAT profile isolates VM from lab VLAN 200–203 fabric; desktop role untouched (no host mutation) |

Post-design re-check (below, after Project Structure): **PASS** — design introduces no
violations. Local pipeline supersedes no repo convention; committed docs land under
`docs/` per repository discoverability expectation.

## Project Structure

### Documentation (this feature)

```text
specs/002-hardened-bootc-pipeline/
├── plan.md              # this file
├── research.md          # Phase 0 — decisions D1–D10 (tempest-concorde analysis)
├── data-model.md        # Phase 1 — entities
├── quickstart.md        # Phase 1 — validation scenarios
├── contracts/
│   ├── pipeline-cli.md        # make/script entry contract
│   ├── hardening-checklist.md # checklist item schema + gate semantics
│   └── execution-record.md    # run-record file schema (state/*.pipeline-run.md)
└── checklists/
    └── requirements.md  # spec-quality checklist (this feature's QA)
```

### Source Code (repository root)

```text
Makefile                          # NEW — thin: pipeline, build, validate, push, vm, clean
bootc/
├── Containerfile                 # MODIFIED — F44 pinned-digest base + hardening
├── config.toml.tmpl              # NEW — bootc-image-builder config (gomplate template)
scripts/
├── pipeline.sh                   # NEW — stage orchestrator (build→scan→validate→push→vm)
├── hardening-verify.sh           # NEW — checklist engine (shell assertions)
└── lib/pipeline-lib.sh           # NEW — shared helpers (ssh, digest capture, records)
docs/
├── tempest-concorde-analysis.md  # NEW — FR-010 committed analysis
└── security-recommendations.md   # NEW — FR-011 committed recommendations
specs/002-hardened-bootc-pipeline/checklists/
└── hardening.md                  # NEW — FR-012 hardening checklist (the deliverable)
state/                            # EXISTING git-ignored — pipeline run records append
```

**Structure Decision**: single-repo layout, mirroring tempest-concorde idioms
(Makefile + scripts + Containerfile at root-level/`bootc/`), with spec-kit docs under
`specs/` and committed analysis docs under `docs/`. Analysis deliverables are committed
(governance), run outputs are git-ignored (`state/`), per constitution and feature-001
convention.

## Complexity Tracking

No constitution violations; no entries required.
