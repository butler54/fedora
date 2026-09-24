# Feature Specification: Capture Current System State

**Feature Branch**: `001-capture-system-state`

**Created**: 2026-09-23

**Status**: Implemented

**Input**: User description: "Capture the current state of the system. The installed packages, the
network configuration, the running containers, services and VMs. Do so by ssh'ing to
chris@donnager-linux. You must not change state of the system at this point in time. Do a
thorough analysis including identifying dead code etc. Capture a summary of the state in
markdown within the project. Do not commit it."

## Clarifications

### Session 2026-09-23

- Q: Should the read-only capture be allowed to use sudo for observational commands? → A: No sudo at all; capture must operate entirely unprivileged, and any observation that would require root is marked "not captured (no sudo)".
- Q: Where should the uncommitted markdown capture report be placed? → A: Under `state/` at the repository root (e.g., `state/donnager-linux-YYYYMMDD.md`), and `.gitignore` MUST be updated to exclude `state/` BEFORE the first capture artifact is written, as a safety net against accidental commits.
- Q: How exhaustive should the installed-package listing be in the capture report? → A: Main report contains a summary (total count, source-repo breakdown, highlights); the full installed-package list is written to a separate appendix file under `state/` alongside the main report.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read-Only Baseline Snapshot (Priority: P1)

As the system owner, I need a single, dated, read-only snapshot of the host
`donnager-linux` covering installed packages, network configuration, running
containers, systemd services, and libvirt virtual machines, so that the
upcoming migration to a bootc-based system is planned against reality rather
than memory.

**Why this priority**: This is the constitutionally mandated first step
(Principle IV — State Capture Before Change). Without this baseline, every
downstream migration decision is unverifiable and regressions will be
indistinguishable from intentional changes.

**Independent Test**: Can be fully tested by reading the capture report and
confirming that all five required domains are populated with real values from
the live host, and by verifying on the host that no mutation occurred during
capture (see Edge Cases).

**Acceptance Scenarios**:

1. **Given** SSH access as `chris@donnager-linux`, **When** the capture runs,
   **Then** a report exists in this project that enumerates installed
   packages, network configuration, containers, services, and VMs with
   values observed on the host.
2. **Given** the capture completed, **When** I inspect `git status` in this
   repository, **Then** the report file is uncommitted and not staged.
3. **Given** the capture completed, **When** I audit the commands run on the
   host, **Then** every executed command is observational (read-only) and no
   package, service, container, VM, network, or filesystem mutation has
   been performed.

---

### User Story 2 - Dead / Orphaned State Findings (Priority: P2)

As the system owner, I need each captured domain annotated to distinguish
in-use state from apparently dead, orphaned, or superseded state (packages
no longer referenced, services enabled but inactive, containers or images
that are stale/exited, orphaned libvirt networks or volumes, repo files
that no longer serve a purpose), so that migration scope is clean and I do
not port drift into the new bootc image.

**Why this priority**: Identifying drift is the primary purpose of the
exercise. Without it, the baseline is just an inventory; with it, the
baseline becomes a migration plan input.

**Independent Test**: Can be fully tested by reading the report's findings
sections and verifying that each domain either lists concrete "dead/suspect"
items with evidence or explicitly records that none were found.

**Acceptance Scenarios**:

1. **Given** the capture has run, **When** I open the report, **Then** each
   domain contains a "Dead / suspect" subsection with items and evidence,
   or an explicit "none identified" statement.
2. **Given** legacy files exist in this repository (e.g., ad-hoc install
   scripts, per-issue runbooks, stale configs), **When** I read the report,
   **Then** the report cross-references which of those repo artifacts appear
   to be superseded by the observed live state (or vice-versa).

---

### User Story 3 - Reviewable In-Project Summary (Priority: P3)

As the system owner, I need the capture delivered as a readable markdown
document inside this project (discoverable, reviewable in one sitting, with
provenance for each observation), kept out of git, so I can iterate on it
before it ever becomes the tracked baseline.

**Why this priority**: This is the delivery format. It matters, but it has no
value independent of Stories 1 and 2, whereas they can be consumed
informally if needed.

**Independent Test**: Can be fully tested by locating the file in this
project, confirming it is exclude-from-git behaviour (uncommitted and, if
desired, covered by `.gitignore`), and confirming its length is reviewable
in one sitting with large raw listings pushed to clearly-linked appendices
or elided.

**Acceptance Scenarios**:

1. **Given** the report exists, **When** I open it, **Then** it has a clear
   structure with the five required domains, a findings section per domain,
   and a provenance note for the commands/queries used.
2. **Given** the report exists, **When** I check repository status, **Then**
   no new commit contains the report and the working tree reflects the
   "do not commit" instruction.

---

### Edge Cases

- **SSH unreachable or auth failure**: capture MUST fail fast with a clear
  message naming the target host and the nature of the failure (network vs
  auth), without partial state in the report.
- **Subsystem absent on host** (e.g., no container runtime, no libvirt):
  the corresponding domain MUST be present in the report with an explicit
  "absent" marker, not silently omitted.
- **Privilege boundary (resolved)**: the capture MUST NOT use sudo or any
  other form of privilege escalation on the target. Observations that can
  only be performed as root MUST be skipped and recorded in the report as
  "not captured (no sudo)" with the name of the observation.
- **Very large listings** (e.g., full installed-RPM list): the main report
  MUST contain only a summary (total count, source-repository breakdown,
  and highlights); the FULL listing MUST be written to a separate appendix
  markdown file in the same `state/` directory and linked from the main
  report. The appendix follows the same no-commit rule as the main
  report.
- **Sensitive-looking strings** (public IPs, ULA addresses, hostname, MACs,
  SSH host keys, user names): acceptable in an uncommitted local report;
  MUST NOT be committed to git. The report itself is the guard.
- **Repo-side dead code**: this repository contains candidate stale artifacts
  (e.g., `installer.yaml`, `install-gcc-13.yaml`, `cuda-install.sh`,
  `scripts/granite-20.sh`, assorted dotfiles). The capture run MUST flag
  which of these are referenced by the observed live state and which appear
  abandoned.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The capture MUST be performed over SSH against the target
  `chris@donnager-linux` using existing credentials/agent configuration;
  no new credentials may be created or stored as part of this feature.
- FR-002 already forbids state change on the target. Additionally, no sudo
  or privilege-escalating command may be invoked during capture.
- **FR-002a**: Any observation that cannot be obtained unprivileged MUST be
  recorded in the report with the explicit marker `not captured (no sudo)`
  and a one-line note of what would have been observed; the capture run
  MUST NOT fail solely because of this.
- **FR-003**: The capture MUST enumerate installed packages (name, version,
  and where distinguishable, source repository) and the total count. The
  main report MUST present this as a summary (total count, per-repository
  counts, and highlights); the complete `name-version` list MUST be
  written to a separate appendix markdown file in `state/` and linked
  from the main report.
- **FR-004**: The capture MUST record network configuration: interfaces,
  addresses, routes, DNS servers, search domains, firewall state, listening
  sockets, and any virtual/bridge networks (including libvirt-managed
  networks).
- **FR-005**: The capture MUST record container-state: runtime(s) in use,
  running and stopped containers, their images, exposed ports, mounts, and
  restart policies.
- **FR-006**: The capture MUST record service state: systemd units that are
  enabled, running, and failed, for both system and the `chris` user
  session.
- **FR-007**: The capture MUST record virtual machine state: libvirt
  domains (defined and running), their key properties (vCPUs, memory,
  disks, network attachments), and storage pools/volumes.
- **FR-008**: The capture MUST record host context relevant to the lab
  role: OS/kernel versions, GPU presence and driver in use, virtualization
  extensions (VT-x/AMD-V, IOMMU), and Secure Boot / disk-encryption status
  as observable from the host.
- **FR-009**: Each observation or summarized claim in the report MUST have
  a provenance entry (the command or query it was derived from) recorded
  in a dedicated provenance section.
- **FR-010**: The report MUST identify dead/suspect items per domain
  (packages, services, containers, VMs, networks) with evidence, or state
  explicitly that none were identified.
- **FR-011**: The report MUST cross-reference this repository's pre-existing
  artifacts (scripts, playbooks, dotfiles, runbooks) against live state and
  flag candidates for removal or rewrite.
- **FR-012**: The report and its appendix MUST NOT be committed to the
  git repository.
- **FR-012a**: Before any capture artifact is written to the repository,
  the project's `.gitignore` MUST be updated to exclude the `state/`
  directory. The presence of this exclusion is a precondition for
  producing the report.

### Key Entities

- **State Snapshot**: A dated, host-scoped capture of the host's observable
  configuration. Attributes: hostname, capture timestamp (UTC), operator
  identity, git ref of this project at capture time.
- **Main Report**: The primary reviewable markdown document. Summarizes
  findings and links to the Appendix Report for long listings.
- **Appendix Report**: A companion markdown artifact that holds
  exhaustive listings (at minimum, the full installed-package list).
  Shares the State Snapshot's date/hostname scope and the same no-commit
  handling as the Main Report.
- **Domain Section**: One of the required domains — packages, network,
  containers, services, VMs, host context. Each contains observations, a
  findings subsection, and provenance references.
- **Finding**: A dead/suspect/drift item. Attributes: domain, identifier
  (package name, unit name, container name, etc.), evidence (short quote
  from observation), suggested disposition (keep / remove / migrate /
  investigate).
- **Provenance Entry**: A recorded command or lookup used to obtain an
  observation. Attributes: command string, host user, whether sudo was
  used, timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One markdown report is produced in this project covering all
  five required domains plus host context, with every domain either
  populated or explicitly marked absent. 100% domain coverage, no silent
  omissions.
- **SC-002**: 100% of actions executed against the target are read-only;
  after the capture, no package, service, container, VM, or network state
  has changed on the host (verifiable by reviewing the provenance list and
  by re-checking host state where appropriate).
- **SC-003**: Every domain contains either a populated "Dead / suspect"
  list with items and evidence, or an explicit "none identified" statement
  — no domain is left ambiguous. Coverage: 5/5 domains plus repo-side
  cross-reference.
- **SC-004**: The report file is present in the working tree, is not
  included in any commit, and the repository's `.gitignore` excludes the
  `state/` directory so that `git status` does not surface the report as
  an untracked candidate.
- **SC-005**: The report names every command or query used to obtain data
  in a single provenance section. A reviewer can reproduce any observation
  using only that section.
- **SC-006**: The main report body is reviewable in one sitting (target:
  readable end-to-end in under 10 minutes). Exhaustive listings (e.g.,
  the full installed-package list) live in a clearly linked appendix file
  in the same `state/` directory, not in the main report.

## Assumptions

- SSH to `chris@donnager-linux` succeeds using the local user's existing
  ssh-agent/keys and `~/.ssh/config`; no interactive password prompts are
  required.
- The capture runs entirely as the unprivileged user `chris`; no sudo is
  used. Observations that would require root are explicitly marked
  `not captured (no sudo)` in the report rather than attempted.
- Output location: a date-stamped markdown file under `state/` at the
  repository root (e.g., `state/donnager-linux-YYYYMMDD.md`). Before the
  first artifact is written, `.gitignore` is updated to exclude `state/`
  so the "do not commit" rule is enforced structurally, not just by
  convention.
- "The system" refers to the primary host `donnager-linux`; no other
  hosts are in scope for this feature.
- "Dead code" is interpreted broadly: applies both to host-level
  configuration drift (orphaned units, stale containers, unused packages
  and networks) and to stale artifacts in this repository
  (`installer.yaml`, `install-gcc-13.yaml`, `cuda-install.sh`,
  `scripts/granite-20.sh`, legacy dotfiles, `nvidia-driver.md`,
  `hard-to-automate.md`) that may be superseded by the as-built state.
- The report may contain sensitive operational detail (hostnames, IPs,
  usernames). Because it is explicitly uncommitted, no redaction is
  required in this iteration.
