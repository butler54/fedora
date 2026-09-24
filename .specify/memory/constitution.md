<!--
SYNC IMPACT REPORT
==================
Version change: (none — template scaffold) → 1.0.0

Modified principles (new, replacing placeholders):
- [PRINCIPLE_1_NAME] → I. Automation-First, Drift-Resistant
- [PRINCIPLE_2_NAME] → II. Image-Based System Definition (bootc)
- [PRINCIPLE_3_NAME] → III. Security as a Non-Negotiable (NON-NEGOTIABLE)
- [PRINCIPLE_4_NAME] → IV. State Capture Before Change
- [PRINCIPLE_5_NAME] → V. Dual-Purpose Awareness (Lab + Desktop)

Added sections:
- Security Requirements
- Development Workflow

Removed sections:
- None (no prior ratified content existed; template placeholders replaced)

Follow-up TODOs:
- None. Ratification date is set to the date of first adoption of real
  content (2026-09-23). If an earlier adoption date is known, amend via
  PATCH-level governance edit.
-->

# Fedora bootc System Management Constitution

## Core Principles

### I. Automation-First, Drift-Resistant

Every system change MUST be expressed as code (Containerfile, config, script,
or declarative manifest) under version control in this repository. Manual
changes are permitted only as probes; the same session that produced them MUST
either codify them or revert them. Step-by-step fixes discovered interactively
MUST be promoted into checked-in automation before the work item is closed.
Rationale: the project exists because a "standard" Fedora install drifted out
of automation; drift is the failure mode this constitution is written against.

### II. Image-Based System Definition (bootc)

The host operating system MUST be defined by a bootc-compatible `bootc/
Containerfile` (or an equivalent single-source image definition). The built
image is the deliverable; the running host is a deployment of that image.
Runtime mutation of the base system (dnf installs, /etc edits that belong in
the image, ad-hoc sysctl changes on the base) is prohibited and MUST be
lifted into the image definition. Day-2 user-layer customization (dotfiles,
user services, per-user tooling) lives outside the image and MUST be managed
separately and reproducibly. Rationale: bootc provides atomic, verifiable,
rollback-capable delivery of the OS; treating the image as the source of
truth is what makes Principle I achievable.

### III. Security as a Non-Negotiable (NON-NEGOTIABLE)

Security is the top priority and MUST NOT be traded for convenience without
an in-repo decision record. The following are required:

- Secure Boot enabled and enforced; verified via `bootctl status` on target
  hosts, with any UEFI firmware quirks documented.
- Full-disk encryption (LUKS) on all deployments of this system.
- Signed, verified boot chain and container images where the ecosystem
  supports it (e.g., cosign-verifiable bootc images); unsigned transport
  MUST be called out as a known gap, not a silent default.
- No secrets, private keys, tokens, or credentials in this repository; use
  an external secret mechanism (e.g., sops + age, or equivalent) and
  reference it from configuration.
- Least privilege by default: minimal sudoers, no passwordless sudo,
  no unnecessary services or listening ports on the base image.
- Third-party RPM repositories and packages MUST be declared in the
  Containerfile and justified; undocumented system-level installs are
  a violation of Principle I and Principle II.
- Necessary-but-fragile flows (NVIDIA akmods, Secure Boot MOK enrollment,
  LUKS interactions) MUST have in-repo runbooks; rely on memory is a
  governance failure.

Rationale: this system runs both a personal desktop and a lab (GPU, LLMs,
libvirt). Compromise in either role endangers the other; the system must
fail closed, not open.

### IV. State Capture Before Change

Before any non-trivial transformation — most importantly the migration from
the current mutable Fedora install to bootc — the as-built state MUST be
captured in this repository: installed packages, enabled services, GPU and
driver configuration, libvirt topology, desktop configuration, and
"hard-to-automate" items explicitly enumerated. Nothing may depend on
the author's memory alone. State capture documents MUST be discoverable
from the repository root. Rationale: the existing install has already
drifted; without a captured baseline, cut-over to bootc cannot be verified
as complete and regressions will be indistinguishable from intentional
changes.

### V. Dual-Purpose Awareness (Lab + Desktop)

The system serves two roles simultaneously: (a) a lab for GPU/LLM
experimentation and libvirt-based virtualization; (b) a daily-driver
desktop. Changes MUST be evaluated against both roles. Lab workloads MUST
be isolated from the desktop host via containers, VMs, or systemd
confinement — not through loosening base-image security. Desktop
convenience features MUST NOT silently disable lab capabilities (e.g.,
GPU passthrough, libvirt networking, VT-d/IOMMU settings). Conflict between
roles MUST be resolved in favour of Security (Principle III); remaining
trade-offs MUST be written down in-repo.

## Security Requirements

The following constraints are binding on every change:

- Secrets hygiene: zero secrets in git; secret references (e.g., sops-encrypted
  files) only. Pre-commit or CI checks MUST detect accidental secrets where
  practical.
- Supply chain: base images pinned by tag AND digest when consumed; RPM
  repositories (including RPM Fusion) enumerated in `bootc/Containerfile`;
  unsigned or unpinned third-party sources are prohibited without an
  in-repo justification.
- Boot and disk security: Secure Boot and LUKS enabled on all production
  targets of this system; deviations MUST be documented as known exceptions
  with an owner and expiry/review date.
- Host attack surface: the base image carries only what is required for the
  two declared purposes; lab tooling that would widen the desktop attack
  surface MUST run inside containers or VMs, not on the host.
- Reference practice: patterns from `tempest-concorde/fedora-bootc-pi`,
  `tempest-concorde/fw-os`, and `tempest-concorde/fw-cicd` SHOULD be
  consulted before inventing new structure; deviations from them MUST be
  intentional and noted.

## Development Workflow

- State capture first: any bootc migration, major driver change (NVIDIA),
  or Secure Boot / LUKS alteration MUST be preceded by a state-capture
  document update (Principle IV) in the same PR or a blocking earlier PR.
- All change lands via pull request; direct commits to the main branch are
  not permitted. PR descriptions MUST state which principles were exercised
  and any intentional exceptions.
- Commit messages follow Conventional Commits (enforced by the existing
  `commitlint.config.js`).
- `bootc/Containerfile` changes MUST be validated by a successful image
  build (locally or in CI) before merge; runtime validation on the target
  host MUST occur before the change is considered done.
- Fragile procedures (NVIDIA akmods, Secure Boot MOK enrollment, LUKS
  interactions, warp.dev-style out-of-band RPMs, DE/UI extension
  management) MUST have or update a runbook in-repo; "I remember how"
  is not an acceptable control.
- Reference projects (`tempest-concorde/fedora-bootc-pi`,
  `tempest-concorde/fw-os`, `tempest-concorde/fw-cicd`) are the default
  source of structural inspiration for this repository (layout, CI,
  image layering); copying/adapting is preferred over novel structure.

## Governance

This constitution supersedes any informal practice or pre-existing note in
this repository where they conflict.

- Amendment procedure: amendments are made by PR against this file. Each
  amendment PR MUST prepend an updated Sync Impact Report HTML comment
  (version change, modified/added/removed principles, deferred TODOs) at
  the top of this file.
- Versioning: this constitution follows SemVer. MAJOR — backward-incompatible
  removal or redefinition of a principle. MINOR — new principle or
  materially expanded section. PATCH — clarifications, wording, typo fixes.
- Compliance review: every PR MUST be reviewed for conformance to this
  constitution (principles, security requirements, and workflow rules).
  Complexity introduced beyond what a principle or section explicitly
  allows MUST be justified in the PR.
- Runtime guidance: this file is authoritative; Spec Kit templates and
  commands query it at execution time and MUST NOT contradict it. Where a
  contradiction is detected, the constitution wins and the contradictory
  artifact MUST be updated.

**Version**: 1.0.0 | **Ratified**: 2026-09-23 | **Last Amended**: 2026-09-23
