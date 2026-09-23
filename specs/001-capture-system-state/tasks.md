# Tasks: Capture Current System State

**Input**: Design documents from `/specs/001-capture-system-state/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not requested in spec — no dedicated test tasks. Lint and acceptance checks are in the Polish phase.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1 / US2 / US3)
- Every task lists the exact file path it touches

## Path Conventions

- Single-project layout: `scripts/`, `.gitignore`, `state/` at repository root
- Capture driver: `scripts/capture-state.sh` (single file; collector tasks in US1 phases are sequential)
- Artifacts: `state/donnager-linux-YYYYMMDD.md` and `state/donnager-linux-YYYYMMDD-packages.md` (git-ignored, never committed)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Pre-flight verification and precondition enforcement.

- [x] T001 Verify prerequisites (`bash` ≥ 5, `ssh`, `git`, `shellcheck`) locally and confirm BatchMode SSH works to `chris@donnager-linux` per `specs/001-capture-system-state/quickstart.md` Q1–Q3.
- [x] T002 [P] Update `.gitignore` at repository root: append a new section `# State capture artifacts (feature 001-capture-system-state)` followed by the single line `state/`. Validate with `git check-ignore -v state/placeholder.md` returning exit 0.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core driver skeleton and helpers. No story work may begin until this phase is complete.

**⚠️ CRITICAL**: All subsequent phases depend on this phase.

- [x] T003 Create `scripts/capture-state.sh` skeleton: shebang `#!/usr/bin/env bash`, `set -euo pipefail`, usage text, CLI parser for `--host`, `--date`, `--out-dir`, `--dry-run`, `--help`, and named exit codes per `specs/001-capture-system-state/contracts/capture-cli.md` (0/1/2/3).
- [x] T004 Implement runtime preconditions inside `scripts/capture-state.sh`: (a) `git check-ignore` succeeds for `<out-dir>/donnager-linux-<date>.md` (FR-012a), (b) `ssh -o BatchMode=yes -o ConnectTimeout=5 <host> 'true'` succeeds, (c) remote `hostname` begins with `donnager-linux`. Any failure exits 2 with a clear stderr message.
- [x] T005 Implement `run_remote` helper in `scripts/capture-state.sh`: executes one allowlisted command over BatchMode SSH, captures stdout to a caller-provided variable, appends a Provenance Entry (side=remote, command, exit, timestamp_utc, sudo=false) to the in-memory provenance log. Handles non-zero exit by returning (not failing) so callers can record `not captured (no sudo)`.
- [x] T006 Implement `--dry-run` mode in `scripts/capture-state.sh`: prints the full allowlisted command inventory grouped by domain with no SSH traffic and no file writes; exits 0.

**Checkpoint**: driver skeleton runs `bash -n` clean, and `--dry-run` prints the inventory without side effects.

---

## Phase 3: User Story 1 — Read-Only Baseline Snapshot (Priority: P1) 🎯 MVP

**Goal**: Produce a populated Main Report and Packages Appendix for `donnager-linux` covering host context, packages, network, containers, services, VMs.

**Independent Test**: Run `scripts/capture-state.sh` to completion (exit 0), then confirm `state/donnager-linux-<date>.md` and `state/donnager-linux-<date>-packages.md` exist, are untracked by git, and every required top-level section is populated or explicitly marked (`absent`, `not captured (no sudo)`).

### Implementation for User Story 1

- [x] T007 [US1] Implement the host-context collector in `scripts/capture-state.sh` (section `## Host Context`): run `hostname`, `hostnamectl`, `uname -a`, `cat /etc/os-release`, `cat /proc/cmdline`, `lscpu`, `lsblk`, `findmnt /`, `getenforce`, `bootctl` (best-effort), `mokutil --sb-state` (best-effort), `ls /sys/kernel/iommu_groups`, `nvidia-smi -L` and `nvidia-smi` (best-effort) and emit the Observations table per `specs/001-capture-system-state/contracts/state-report.md`.
- [x] T008 [US1] Implement the packages collector in `scripts/capture-state.sh`: run `rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{VENDOR}\n' | sort` for the full list (→ appendix) and `dnf -q repoquery --installed --qf '%{name}\t%{reponame}'` for per-repository counts (degrade to `unknown-repo` if dnf repoquery unavailable); write `state/donnager-linux-<date>-packages.md` per contract and emit the summary Observations table in `## Packages` of the Main Report.
- [x] T009 [US1] Implement the network collector in `scripts/capture-state.sh` (section `## Network`): `ip -brief address`, `ip -brief link`, `ip route`, `ip -6 route`, `resolvectl status`, `cat /etc/resolv.conf`, `ss -tulpn`, `nmcli -t general status`, `firewall-cmd --state`, `firewall-cmd --get-default-zone`; record `not captured (no sudo)` for observations that fail due to privilege.
- [x] T010 [US1] Implement the containers collector in `scripts/capture-state.sh` (section `## Containers`): detect `podman` and/or `docker`; if neither exists emit `absent`. Otherwise collect `podman ps -a --format ...` (or `docker ps -a`), `podman images --format ...`, `podman network ls`, `podman volume ls`, and top of `podman system info`. Mark user-scoped daemon failures as `not captured (no sudo)`.
- [x] T011 [US1] Implement the services collector in `scripts/capture-state.sh` (section `## Services`): `systemctl list-unit-files --state=enabled`, `systemctl --failed`, `systemctl list-units --type=service --state=running` — each for system and `--user`; if the user systemd manager is unreachable, use marker `not captured (user systemd unavailable)`.
- [x] T012 [US1] Implement the VMs collector in `scripts/capture-state.sh` (section `## Virtual Machines`): detect `virsh`; if missing emit `absent`. Otherwise run `virsh list --all`, `virsh net-list --all`, `virsh pool-list --all` against the default user URI only (do NOT attempt `qemu:///system` per Clarification Q1), marking `not captured (no sudo)` for anything that fails for privilege reasons.
- [x] T013 [US1] Implement the Main Report renderer in `scripts/capture-state.sh`: snapshot header block (hostname, FQDN, captured_at_utc, operator, project_git_ref=`git rev-parse --short HEAD`, feature_id=`001-capture-system-state`), the fixed section order from `specs/001-capture-system-state/contracts/state-report.md`, the Provenance table appended at the end, and final write to `state/donnager-linux-<date>.md` (overwrite-same-day allowed).
- [x] T014 [US1] Execute a live capture: run `scripts/capture-state.sh`; expect exit 0 and both artifacts produced. Confirm with quickstart Q4: artifacts exist, `git status --porcelain state/` empty (ignored), and remote state unchanged.

**Checkpoint**: Main Report + Appendix exist and satisfy SC-001 (all 6 domains populated or explicitly marked).

---

## Phase 4: User Story 2 — Dead / Orphaned State Findings (Priority: P2)

**Goal**: Every domain has an explicit Findings subsection — populated with evidence-backed dead/suspect items or `none identified` — and a Repo Artifacts cross-reference table exists with reviewer-driven dispositions.

**Independent Test**: For each of the six domains plus Repo Artifacts in `state/donnager-linux-<date>.md`, verify the `### Findings` block is either a populated table with `Item | Evidence | Suggested disposition | Note` or the literal `none identified`; Repo Artifacts rows have a non-`TODO` disposition after the reviewer pass.

### Implementation for User Story 2

- [x] T015 [P] [US2] Implement Findings scaffolding in `scripts/capture-state.sh`: for each domain, auto-suggest candidates from the observations (services: enabled-but-inactive, failed units; containers: stopped > 30 days, dangling images, unused named volumes/networks; packages: guardedly call `package-cleanup --leaves 2>/dev/null` if available, else skip; VMs/networks: defined but never run / no attached guests) into the Findings table with `Suggested disposition = investigate`. Reviewer edits decide final disposition.
- [x] T016 [P] [US2] Implement the Repo Artifacts table emitter in `scripts/capture-state.sh` (section `## Repo Artifacts`): fixed rows for `installer.yaml`, `install-gcc-13.yaml`, `cuda-install.sh`, `scripts/granite-20.sh`, `nvidia-driver.md`, `hard-to-automate.md`, `thunderbird.md`, `bash_profile`, `bashrc`, `gpg-agent.conf`, `gpg.conf`, `ssh-config`, `bootc/Containerfile`, plus `specs/` and `.specify/` as directory-level entries, with columns per `contracts/state-report.md` and `Disposition = TODO` placeholder.
- [x] T017 [US2] Reviewer pass: re-read `state/donnager-linux-<date>.md` after generation and update it in place — for every Findings row set a terminal `Suggested disposition` (`keep`, `remove`, `migrate`, `investigate`) backed by quoted evidence, and convert every Repo Artifacts `TODO` disposition to a terminal value (`keep`/`remove`/`migrate`/`investigate`) with a reviewer note. This is deliberately a non-automated judgement step.
- [x] T018 [US2] Validate SC-003: confirm (a) every domain Findings block is populated or literal `none identified`, and (b) every Repo Artifacts row has a non-`TODO` disposition. Re-run the capture to confirm results are stable and idempotent (same-day overwrite).

**Checkpoint**: SC-003 satisfied; report is migration-planning-ready.

---

## Phase 5: User Story 3 — Reviewable In-Project Summary (Priority: P3)

**Goal**: The Main Report is reviewable end-to-end in under 10 minutes (≤ 800 lines), links cleanly to the Packages Appendix, and is verifiably untracked by git.

**Independent Test**: `wc -l state/donnager-linux-<date>.md` ≤ 800, appendix linked from `## Packages`, `git log --all -- 'state/'` empty, and a fresh reader can locate the provenance for any claim within 1 hop.

### Implementation for User Story 3

- [x] T019 [US3] Add a line-count guard in `scripts/capture-state.sh`: after writing the Main Report, count lines; if > 800, print a stderr warning identifying the offending section sizes. Trim logic: package lists never inlined; long `nvidia-smi --query` style outputs capped at 40 lines with `head -n 40`.
- [x] T020 [US3] Finalize Snapshot header and editorial pass of the Main Report: verify all Snapshot fields populated (hostname, FQDN, captured_at_utc, operator, project_git_ref, feature_id), ensure prose in `### Notes` sections is concise, and correct any heading deviation from `contracts/state-report.md`.
- [x] T021 [US3] Run quickstart Q5 validation in `specs/001-capture-system-state/quickstart.md`: heading order (9 top-level `##` headings), ≥ 6 `### Findings` blocks, provenance row count ≥ 20, appendix `## Packages (N total)` matches Main Report `total installed`, main report line count ≤ 800. Fix any mismatch in the driver and re-run.
- [x] T022 [US3] Run quickstart Q6 validation: confirm provenance contains only read-only invocations, `Sudo` column is `no` for every row, and spot-check two counts (installed RPMs, running systemd services) directly over SSH match the report within jitter.

**Checkpoint**: Report is end-to-end reviewable; all Success Criteria in `specs/001-capture-system-state/spec.md` are demonstrably met.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Lint, hardening, and final acceptance evidence.

- [x] T023 [P] Run `bash -n scripts/capture-state.sh` and `shellcheck scripts/capture-state.sh`; resolve all errors and triage warnings. Re-run until clean.
- [x] T024 [P] Add header comment block and example invocations to `scripts/capture-state.sh` (purpose, read-only guarantee, no-sudo guarantee, FR references, usage examples) following the style of existing scripts in `scripts/`.
- [x] T025 Run the full quickstart (`specs/001-capture-system-state/quickstart.md` Q1–Q6) as the final acceptance pass; record the outcome (pass/fail per check) in a new `state/donnager-linux-<date>.acceptance.md` (also uncommitted, also inside the git-ignored directory).
- [x] T026 Update `specs/001-capture-system-state/spec.md` Status field from `Draft` to `Implemented`. Do not commit anything — user will commit code changes deliberately; `state/` artifacts remain untracked by design.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — immediate.
- **Foundational (Phase 2)**: Depends on Phase 1 (gitignore precondition in particular). BLOCKS all stories.
- **US1 (Phase 3)**: Depends on Foundational only. Can be tested alone (MVP).
- **US2 (Phase 4)**: Depends on US1 (needs a generated Main Report to annotate via T017). Findings scaffolding (T015/T016) can be developed in parallel with US1 collectors but runs after T013 exists.
- **US3 (Phase 5)**: Depends on US1 + US2 (final artifact is what gets reviewed).
- **Polish (Phase 6)**: Depends on all three stories.

### User Story Dependencies

- **US1 (P1)**: Independent baseline — no dependency on US2/US3.
- **US2 (P2)**: Requires a live Main Report from US1 to annotate; independent of US3.
- **US3 (P3)**: Produces the accepted, final reviewable artifact — requires US1 and US2 to be complete.

### Within Each User Story

- US1: collectors (T007–T012) are sequential (same file `scripts/capture-state.sh`); renderer (T013) last; live run (T014) final validation.
- US2: T015/T016 can be developed in parallel (different sections of the same script but non-overlapping code paths); T017 requires a generated report; T018 is terminal.
- US3: T019 → T020 → T021 → T022, strictly sequential.

### Parallel Opportunities

- T001 and T002 in Setup are parallel (different concerns, no shared file).
- T015 and T016 in US2 are parallel (independent emitter functions).
- T023 and T024 in Polish are parallel (same file but disjoint content areas — lint fixes and header docs).
- Collector T007–T012 are explicitly serial (single-file evolution).

---

## Parallel Example: Setup

```bash
# Run in parallel:
Task: "Verify prerequisites per quickstart.md Q1–Q3"
Task: "Update .gitignore with state/ exclusion"
```

---

## Parallel Example: User Story 2

```bash
# Run in parallel (distinct functions in scripts/capture-state.sh):
Task: "Implement Findings scaffolding"
Task: "Implement Repo Artifacts table emitter"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational)
2. Complete Phase 3 (US1) through T014
3. **STOP and VALIDATE**: artifacts exist, all 6 domains populated or `absent`/`not captured (no sudo)`, `git status` clean
4. Demo: walk the Main Report in one sitting

### Incremental Delivery

1. Setup + Foundational → driver skeleton ready
2. US1 → baseline snapshot produced (MVP!)
3. US2 → findings annotated; drift analysis complete
4. US3 → report is reviewable end-to-end within ~10 minutes
5. Polish → lint clean, quickstart fully green, spec status updated

### Sequential Strategy (single operator)

T001 → T002 → T003 → T004 → T005 → T006 → T007 → … → T014 → T015 → T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023 → T024 → T025 → T026

---

## Notes

- [P] tasks = different files or disjoint code areas; safe to run concurrently.
- [US1]/[US2]/[US3] labels map tasks to the user stories in `specs/001-capture-system-state/spec.md`.
- No test tasks generated (spec did not request tests); acceptance is via quickstart Q1–Q6 in US3/Polish.
- Nothing in these tasks commits to git. `state/` is and remains untracked; `.gitignore` modification is in the user's working tree and follows the repo's own PR workflow separately.
