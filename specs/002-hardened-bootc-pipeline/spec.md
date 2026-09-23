# Feature Specification: Hardened Fedora 44 bootc VM Pipeline

**Feature Branch**: `002-hardened-bootc-pipeline`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "based on the analysis create an end to end pipeline for a fedora 44 vm
in as locked down method as possible, based on the repos in tempest-concorde. Fundamental analysis
of the tempest-concorde repos can be done. Security analysis can recommend further changes. Ensure
a hardening checklist is built."

## Clarifications

### Session 2026-09-23

- Q: How should the hardened VM handle remote shell access by default? → A: "Hardened" refers to the build process (pinned, reproducible, verified), SELinux enforcement, and the update process — NOT to stripping runtime services. SSHD is required as the VM remains a user-facing machine: installed and enabled by default, public-key authentication only, password authentication disabled, listening on the checklist-enumerated port (default tcp/22) which is pre-accounted for in the hardening checklist.
- Q: Under which network attachment should the hardened VM be produced by default? → A: Default profile attaches to the user-session libvirt NAT network (outbound-capable, private). The pipeline design must accommodate future profiles — internet-connected attachments (e.g., lab-VLAN bridged) and fully isolated networks — since lab scenarios will need a mix of both. Profile selection beyond the default is out of scope for this feature but the parameterization seam must exist.
- Q: How should VM images be distributed and updated end-to-end? → A: The pipeline pushes built images to an OCI registry, and the VM's automatic-update mechanism pulls from that registry via `bootc upgrade`. No rebuild-and-swap lifecycle for the default path.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - End-to-End Locked-Down VM Pipeline (Priority: P1)

As the system owner, I need a single, repeatable pipeline defined in this repository that
takes the repo's declarative OS definition and produces a bootable Fedora 44 VM on my lab
host with a locked-down default posture, so that every VM I spin up for lab work starts
hardened rather than hardened-after-the-fact.

**Why this priority**: Without this, every lab VM is a bespoke act of manual effort and the
security posture drifts per-VM — the exact failure mode the project constitution was
ratified to prevent (Principles I, III).

**Independent Test**: From a clean checkout of this repository, run the documented pipeline
entry point; confirm it produces a VM that boots to a login prompt on the lab host, and
confirm the VM's default posture matches the lockdown requirements (FR-005, FR-009) with
no manual steps.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** the pipeline is invoked via its single documented
   entry point, **Then** it builds the image, runs its validation gate, and produces a
   VM definition ready to boot — with no prompts and no outside-repo edits.
2. **Given** the VM has been produced, **When** it is started on the lab host, **Then**
   it reaches a login prompt without interactive provisioning steps.
3. **Given** a running VM, **When** its listening services are enumerated, **Then**
   every listener is accounted for in the hardening checklist (with tcp/22 sshd
   pre-accounted as the baseline admission).

---

### User Story 2 - Hardening Checklist as the Release Gate (Priority: P2)

As the system owner, I need a named, versioned hardening checklist that every pipeline run
verifies the built image against, with machine-checkable items executed automatically and
the run failing closed on any failed check, so that "as locked down as possible" is a
testable claim rather than an intention.

**Why this priority**: The user explicitly mandated the checklist as a feature deliverable
and it is the acceptance contract for US-1. A pipeline without a fail-closed checklist is
an automation of hope.

**Independent Test**: Introduce a deliberate violation (e.g., a package addition that
opens a listener) in a test branch, run the pipeline, and confirm the checklist gate
fails and no VM is produced. Then revert and confirm the gate passes.

**Acceptance Scenarios**:

1. **Given** the hardening checklist exists, **When** the pipeline runs, **Then** every
   automatable item is executed and its pass/fail recorded in the run's output record.
2. **Given** any checklist item fails, **When** the pipeline completes, **Then** the run
   is marked failed and no VM artifact is left in a "ready" state.
3. **Given** items that cannot be automated, **When** I inspect the checklist, **Then**
   each such item is explicitly marked manual-verify with a named owner and a due date or
   permanent-review status.

---

### User Story 3 - tempest-concorde Analysis + Security Recommendations (Priority: P3)

As the system owner, I need committed, in-repo analysis documents covering (a) the
fundamental patterns of the tempest-concorde reference repositories
(`fedora-bootc-pi`, `fw-os`, `fw-cicd`) — adopted or rejected with rationale — and
(b) security recommendations flowing from that analysis combined with the feature-001
live-state findings, so that this pipeline's structure is provably informed rather than
invented.

**Why this priority**: The user called for "fundamental analysis" and "security analysis
recommending further changes." It shapes long-term direction but the pipeline (US-1) and
its gate (US-2) demonstrably deliver the feature's core value without this document
blocking them.

**Independent Test**: Open the two committed documents. Confirm the patterns document
evaluates each of the three named repos and records adopt/reject per pattern with a
rationale; confirm the recommendations document lists prioritized actions each backed
by evidence (analysis finding or feature-001 observation).

**Acceptance Scenarios**:

1. **Given** the feature is implemented, **When** I look in the repository, **Then** I
   find a committed document covering all three tempest-concorde repositories with
   adopt/reject decisions per major pattern (image layering, CI shape, update model).
2. **Given** the recommendations document, **When** I read its actions, **Then** every
   action references either a specific tempest-concorde pattern or a specific
   feature-001 finding (e.g., unexplained port 80 listener, 86 empty-vendor RPMs,
   IOMMU disabled).

---

### Edge Cases

- **Base image drift**: the upstream Fedora 44 base image moves between pipeline runs —
  the pipeline MUST record the exact digest used and MUST be able to build against a
  pinned recorded digest on demand.
- **Checklist regression in trivial-looking change**: the gate MUST fail closed by
  default; there is no "warn and continue" mode.
- **VM name/domain collision** on the lab host: the pipeline MUST refuse to overwrite an
  existing domain; cleanup of a prior run's VM is an explicit separate action.
- **Host GPU/IOMMU unavailable (feature-001 finding)**: the baseline VM MUST NOT depend
  on GPU passthrough; GPU/VFIO variants are explicitly out of scope for this feature.
- **Disk pressure on the lab host**: pipeline must report a clear, actionable error
  naming the required free space rather than failing mid-build with an opaque error.
- **Nested virtualization availability mismatch**: if the lab host cannot schedule a
  KVM guest, the pipeline fails fast at the validation step, not at first boot.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST contain a single declarative OS definition targeting
  Fedora 44 as the base, replacing-or-extending `bootc/Containerfile` so the VM's
  entire software surface is defined in-repo.
- **FR-002**: The pipeline MUST have exactly one documented entry point, runnable from
  the repository root, that performs: build → validate (hardening gate) → produce
  runnable VM on the lab host.
- **FR-003**: The pipeline MUST execute the hardening checklist's automatable items
  against the built image before the VM is accepted, and MUST fail closed on any
  failed automatable item (exit non-zero, no "ready" VM left behind).
- **FR-004**: The produced VM MUST boot on the lab host's QEMU/KVM stack via libvirt
  user session (no host-side root daemons modified), reaching a login prompt without
  interactive provisioning.
- **FR-005**: The locked-down posture targets three pillars — build integrity,
  runtime mandatory-access-control, and update hygiene. MUST include:
  (a) build integrity — reproducible build from a pinned base-image digest
  with per-run provenance recorded (FR-007, FR-008);
  (b) runtime — SELinux Enforcing; firewall default-deny inbound with tcp/22
  (sshd) as the single pre-authorized inbound service; sshd public-key-only
  (password authentication and root login disabled);
  (c) update hygiene — the pipeline pushes the built image to an OCI
  registry; the VM's automatic update mechanism (bootc upgrade on a
  systemd timer) pulls from that registry reference; reboot-or-staged-apply
  policy documented; no secrets baked into the image and registry
  credentials never embedded in the image or committed to this repository.
  The disk-encryption story is documented (VM-level LUKS or explicit
  rationale referencing host LUKS).
- **FR-006**: The image MUST NOT introduce listeners beyond those enumerated
  in the hardening checklist with a justification; tcp/22 (sshd) is
  pre-enumerated in the checklist as the baseline admitted listener.
- **FR-006a**: The pipeline MUST attach the VM to the user-session libvirt NAT
  network by default. The network attachment MUST be a parameter of the
  pipeline (not scattered through scripts) so that future profiles —
  lab-VLAN bridged attachment and fully isolated networks — can be added
  without redesign. Implementing those additional profiles is out of scope
  for this feature.
- **FR-007**: The pipeline MUST produce an execution record per run (timestamp,
  repo commit, base-image digest, built-image digest, registry reference it
  was pushed to, checklist outcomes, VM domain
  name) written under the git-ignored `state/` directory in the same style as
  feature 001.
- **FR-007a**: The pipeline MUST push the validated image to the designated
  OCI registry before the VM is accepted, and the produced VM MUST boot
  referencing that registry image so that `bootc upgrade` pulls subsequent
  builds from the same reference. Registry push MUST fail closed: a failed
  push blocks VM acceptance as surely as a failed checklist item.
- **FR-008**: The built image MUST be reproducible — re-running the pipeline from
  the same repo commit and same pinned base digest yields the same built-image
  digest (modulo explicitly recorded entropy such as key generation).
- **FR-009**: The pipeline MUST NOT mutate host security posture: no new host
  packages outside the bootc image, no host firewall changes, no host service
  changes, no host kernel/module changes. Verifiable by re-running the feature-001
  capture script before/after.
- **FR-010**: The repository MUST contain a committed analysis document evaluating
  `tempest-concorde/fedora-bootc-pi`, `tempest-concorde/fw-os`, and
  `tempest-concorde/fw-cicd`, recording for each major pattern an adopt / adapt /
  reject decision with rationale.
- **FR-011**: The repository MUST contain a committed security-recommendations
  document whose every item is prioritized (P1/P2/P3) and traces to either a
  tempest-concorde pattern or a feature-001 live-state finding.
- **FR-012**: The hardening checklist MUST live under `specs/002-hardened-bootc-pipeline/checklists/hardening.md`,
  with every item marked automatable (with its command) or manual-verify (with
  named owner and review status).

### Key Entities

- **Image Definition**: the declarative OS source (commit-pinned base + package
  set + config overlay) from which the VM image is built. Lives in-repo.
- **Pipeline Run**: one end-to-end execution; attributes: repo commit, base
  digest, built digest, checklist result set, VM domain name (if released).
- **Hardening Checklist Item**: single control. Attributes: id, description,
  automatable (bool), command-or-procedure, evidence expected, owner, status
  per run.
- **VM Domain**: libvirt domain produced by a released run. Attributes: name,
  source digest, storage path, boot mode (UEFI/secure-boot), network attachment.
- **Analysis Document** and **Recommendations Document**: committed markdown
  artifacts (FR-010, FR-011).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One command from a clean checkout completes the pipeline end-to-end
  and yields a VM domain on the lab host, total wall time ≤ 30 minutes on the
  observed lab hardware, with zero manual interventions.
- **SC-002**: The produced VM reaches a login prompt within 2 minutes of first
  boot on the lab host.
- **SC-003**: 100% of automatable hardening checklist items execute per run and
  the run fails (no ready VM) if any single item fails. Manual-verify items are
  100% enumerated with owners in the run record.
- **SC-004**: Post-boot enumeration of the VM shows zero unaccounted
  internet-facing listeners (measurement method matches feature-001's network
  check).
- **SC-005**: Both analysis documents are committed in-repo; adop/reject
  coverage is 3/3 reference repositories; every recommendation traces to a named
  source (reference-repo pattern or feature-001 finding).
- **SC-006**: Two consecutive pipeline runs from the same commit and pinned base
  digest produce identical built-image digests.
- **SC-007**: Feature-001 capture script re-run after pipeline completion shows
  zero host-regression findings introduced (no new unexplained listeners, no new
  failed services, no new packages outside the bootc image path).

## Assumptions

- Target hypervisor: QEMU/KVM via libvirt user session on the existing lab host
  (`donnager-linux`); user-session libvirt was verified functional in feature 001
  (a test domain already exists). System-session `qemu:///system` is out of scope
  per the no-sudo day-0 constraint.
- VM has no GPU passthrough and does not need IOMMU; GPU/VFIO flows are a
  separate future feature (feature-001 shows IOMMU is currently disabled and is
  its own work item).
- The Fedora 44 bootc base image for the VM is published upstream
  (`quay.io/fedora/fedora-bootc:44` or documented successor); its digest is
  pinned per FR-008/Edge Case.
- The tempest-concorde reference repositories are publicly readable from the
  authoring environment; analysis happens during this feature's planning phase
  and its committed outputs land via FR-010/FR-011.
- VM traffic egress is allowed (updates, package metadata, model pulls);
  what we lock down is build integrity, SELinux, inbound posture (sshd-only
  by default), update hygiene, and host-boundary hygiene — offline
  operation is not a requirement.
- Registry: default is a private repository on a registry service (initial
  choice recorded in the plan; `quay.io` private repository is the
  reasonable default given the tempest-concorde reference patterns).
  Registry credentials are referenced from the environment/host secret
  store at pipeline time only — never committed, never inside the image.
- The bootc upgrade pull in the VM uses the public-or-authenticated
  registry reference configured at image build time; any pull secret for a
  private repo is provisioned via cloud-init from host-side input, not
  baked into the image.
- VM storage encryption: default is no VM-level LUKS (the lab host root is
  LUKS-encrypted; VM volumes reside on it). This is recorded as a checklist
  manual-verify item with explicit rationale, not a silent omission.
- The pipeline runs on a Fedora-family toolchain (the lab host itself);
  macOS hosts are not required to execute the pipeline — authoring machine
  uses the lab host over SSH (same pattern as feature 001).
