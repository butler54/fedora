# Tasks: Hardened Fedora 44 bootc VM Pipeline

**Input**: Design documents from `/specs/002-hardened-bootc-pipeline/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: No dedicated TDD tasks requested. US2's fixture + negative-gate proof tasks are the spec's own acceptance mechanism (fail-closed checklist) and are included as story tasks.

**Organization**: Tasks grouped by user story; foundational phase blocks all stories.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: different files, no dependency on an incomplete task
- **[Story]**: US1 (pipeline), US2 (hardening checklist gate), US3 (analysis docs)
- Every task names exact file paths

## Path Conventions

- Repo root single-project layout: `Makefile`, `bootc/`, `scripts/`, `docs/`, `state/` (git-ignored)
- Feature artifacts: `specs/002-hardened-bootc-pipeline/checklists/hardening.md`
- Pipeline executes on `chris@donnager-linux` over BatchMode SSH from the authoring host

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: close access gaps and land the verified pin values the pipeline depends on.

- [x] T001 Re-establish BatchMode SSH to `chris@donnager-linux` (re-add agent identity, e.g. `ssh-add` YubiKey key) and verify: `ssh -o BatchMode=yes chris@donnager-linux true` succeeds with no prompt.
- [x] T002 [P] Run quickstart Q0.1 bundle verification on the lab host (`ssh chris@donnager-linux 'dnf group info container-management'`) and append the output verbatim to `state/donnager-linux-20260923.pipeline-notes.md` as decision evidence for research.md D5.
- [x] T003 [P] Run quickstart Q0.2 (`dnf list --available "akmod-nvidia*" "kmod-nvidia*"` on the host), append the matrix (package, version, repo) to `state/donnager-linux-20260923.pipeline-notes.md` as decision evidence for research.md D6.
- [x] T004 [P] Resolve and pin digests: `ssh chris@donnager-linux podman inspect quay.io/fedora/fedora-bootc:44` (or skopeo) and `quay.io/centos-bootc/bootc-image-builder:latest`; write `bootc/variables.env` containing `BASE_DIGEST=`, `BUILDER_DIGEST=`, `REGISTRY_REF_DEFAULT=quay.io/<namespace>/hardened-f44:latest` (namespace placeholder OK — parameterized at runtime).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: repo assets every stage and every story relies on. No story work starts until this is complete.

- [x] T005 Rewrite `bootc/Containerfile`: FROM `<quay.io/fedora/fedora-bootc:44@sha256:${BASE_DIGEST}>`; dnf install via **groups** only (e.g. `@container-management`; zero GUI groups) with per-package entries reserved for tools with no group home; embed sshd hardening drop-in (`/etc/ssh/sshd_config.d/50-hardened.conf`: PasswordAuthentication no, PermitRootLogin prohibit-password or no, KbdInteractiveAuthentication no) as an image file; embed `bootc-fetch-apply-updates.timer` enablement via a systemd preset drop-in (`/etc/systemd/system-preset/90-hardened.preset`); imageLabel `org.opencontainers.image.source` pointing at this repo. Document bundle choice rationale inline in comments.
- [x] T006 Create `bootc/config.toml.tmpl` (gomplate template per tempest-concorde pattern) for bootc-image-builder: `customizations.user` (name `chris`, locked password, `groups: ["wheel"]`, `ssh_authorized_keys` from env `SSH_PUBKEY`), `customizations.services` (enable sshd; bootc fetch-apply-updates timer), `customizations.hostname` default `f44-hardened`, and `customizations.files` block writing `/etc/ostree/auth.json` from env-provided registry pull secret when `REGISTRY_PULL_SECRET` is set (only at VM-create time, never committed).
- [x] T007 Create `scripts/lib/pipeline-lib.sh`: `log/warn/die`, `run_remote` (BatchMode ssh with provenance timestamps), `cap_json_end` iteration helpers, `record_kv` + `record_append` writers emitting the `contracts/execution-record.md` per-run markdown block into `state/donnager-linux-$(date -u +%Y%m%d).pipeline-run.md`, `digest_of_image` (podman inspect → sha256), and `smoke_vm_start`/`smoke_vm_destroy` helpers (user-session virsh, transient domain, destroy guaranteed via trap).
- [x] T008 Create `scripts/pipeline.sh`: `set -euo pipefail`, CLI parse for `--host --registry-ref --vm-name --vcpus --memory-mib --disk-gib --network-profile --dry-run --help`, stage runner framework with per-stage functions (`stage_preflight`, `stage_build`, `stage_scan`, `stage_validate`, `stage_push`, `stage_vm`) initially calling lib stubs, exit codes exactly per `contracts/pipeline-cli.md` (0/1/2/3/4/5/6/7), and per-stage duration capture into the execution record.
- [x] T009 Create `Makefile` with facade targets `pipeline`, `build`, `validate`, `push`, `vm`, `clean`, `dry-run` mapping to `scripts/pipeline.sh` with matching flags; default `pipeline`; `make clean` requires interactive confirm and only removes the named VM + its volume (never touches host or host services).
- [x] T010 Author `specs/002-hardened-bootc-pipeline/checklists/hardening.md` with every item in contract schema (`contracts/hardening-checklist.md`): H001–H004 (build pillar), H010–H015 (runtime pillar), H020–H022 (updates pillar), H030–H031 (pipeline), H040–H041 (manual-verify, owner `chris`). Include the baseline admitted-listener table with exactly `tcp/22` and note H014's comparison set lives here.

**Checkpoint**: `bash -n` clean on scripts; `make dry-run` prints stage plan without touching the host.

---

## Phase 3: User Story 1 — End-to-End Locked-Down VM Pipeline (Priority: P1) 🎯 MVP

**Goal**: `make pipeline` from a clean checkout produces a bootable, locked-down Fedora 44 VM on the lab host, end-to-end, no manual steps.

**Independent Test**: fresh clone or clean working tree; run `make pipeline`; VM boots to login prompt locally (≤ 2 min) and key-only SSH from the host works; execution record shows `released`.

### Implementation for User Story 1

- [ ] T011 [US1] Implement `stage_preflight` in `scripts/pipeline.sh`: BatchMode ssh probe (fail exit 2), `state/` git-ignore verification (FR-012a-style), ≥ 40 GiB free check in the VM volume dir on host, digest-pin equality check between `bootc/variables.env` and upstream (`skopeo inspect` or `podman inspect` via the host) with clear drift error.
- [ ] T012 [US1] Implement `stage_build` in `scripts/pipeline.sh`: remote `podman build -f bootc/Containerfile` on the lab host using build context rsynced to a user-home temp dir; **lid**: verify no declared package is inside a declared group (reads the Containerfile manifest, queries `dnf repoquery --groupmember` on host), and dump each declared group's `dnf group info` output into the run record (`contracts/execution-record.md` Bundle manifest section); exit 3 on failure.
- [ ] T013 [US1] Implement `stage_scan` in `scripts/pipeline.sh`: run `scripts/hardening-verify.sh --phase image --image <id>` on the lab host in a throwaway `podman run --rm` container mounting the built image rootfs; gate result to the execution record.
- [ ] T014 [US1] Implement `stage_push` in `scripts/pipeline.sh`: read `QUAY_USER`/`QUAY_TOKEN` from env (fail loudly if absent), `podman login` non-interactively, retag built image to `REGISTRY_REF`, push, re-resolve pushed digest, record as `built_image_digest` + `registry_ref`; exit 5 on failure.
- [ ] T015 [US1] Implement `stage_vm` in `scripts/pipeline.sh`: render `bootc/config.toml.tmpl` via `gomplate` using env (`SSH_PUBKEY` from `ssh-add -L` matching `SSH_KEY_PATH`, `REGISTRY_PULL_SECRET` if private repo), run digest-pinned `quay.io/centos-bootc/bootc-image-builder` in podman on the host to produce QCOW2 in the user libvirt pool directory, then `virt-install --import --os-variant fedora-unknown` (or `virsh define` XML) under `qemu:///session` with name `$VM_NAME` + 4 vCPU/8192 MiB/60 GiB defaults + NAT user-session network; **collision** (existing domain or volume) ⇒ exit 7 without touching the existing resource; start domain and wait for guest agent or DHCP lease, record NAT address; exit 6 on failure.
- [ ] T016 [US1] Implement `stage_validate` in `scripts/pipeline.sh`: create a **transient smoke VM** via `smoke_vm_start` (lib helper; distinct suffixed name; NAT), wait for ssh-ready, run `scripts/hardening-verify.sh --phase runtime --target ssh://chris@<smoke-ip>`, guarantee `smoke_vm_destroy` via trap even on failure; record verdicts; exit 4 if any item FAIL.
- [ ] T017 [US1] Implement execution-record finalization in `scripts/pipeline.sh`: assemble the full per-run block per `contracts/execution-record.md` (stages, durations, digests, bundle lid verdicts, hardening matrix, VM section), append to `state/donnager-linux-<date>.pipeline-run.md`, print released/failed summary to stdout.
- [ ] T018 [US1] Live acceptance run: `make pipeline` end-to-end on the lab host; run quickstart Q3 and Q4 (login-prompt ≤ 2 min observation, key-only ssh from host, `bootc status` image ref == REGISTRY_REF) and record outputs in the run record Notes.

**Checkpoint**: US1 independently delivers the hardened VM. SC-001/SC-002/SC-004 demonstrably met.

---

## Phase 4: User Story 2 — Hardening Checklist as the Release Gate (Priority: P2)

**Goal**: checklist is fully executable by `scripts/hardening-verify.sh`, and the gate provably fails closed (blocks release) on violation.

**Independent Test**: per quickstart Q2 — broken fixture fails the gate; healthy fixture passes — and per US2 acceptance: a deliberately non-compliant build input aborts the pipeline with no VM released.

### Implementation for User Story 2

- [x] T019 [P] [US2] Create fixture generators `scripts/fixtures/broken-image/` (Containerfile variant with `PasswordAuthentication yes` and an extra open port baked) and `scripts/fixtures/healthy-image/` (passes all automatable items), each with a README line explaining which checklist item it trips/passes.
- [x] T020 [US2] Implement every automatable check command in `scripts/hardening-verify.sh` for items H001–H004, H010–H015, H020–H022, H030–H031 exactly as declared in `specs/002-hardened-bootc-pipeline/checklists/hardening.md`, with dual-phase support (`--phase image|runtime`), item-id selection (`--only H010`), and verdict-matrix emission matching `contracts/hardening-checklist.md`.
- [ ] T021 [US2] Negative-gate proof: run `scripts/pipeline.sh` against the broken fixture as build input (fixture-mode flag); assert exit code 4, no `f44-hardened-*` domain released, and the run record shows `failed` with the failing item IDs; capture terminal + record excerpts into `state/donnager-linux-<date>.pipeline-acceptance.md`.
- [x] T022 [US2] Positive-gate proof: run engine directly against the healthy fixture (`--against fixture:healthy`), assert exit 0 and a full-PASS matrix; append evidence to `state/donnager-linux-<date>.pipeline-acceptance.md`.

**Checkpoint**: gate proven fail-closed (negative) and functional (positive). SC-003 demonstrably met.

---

## Phase 5: User Story 3 — tempest-concorde Analysis + Security Recommendations (Priority: P3)

**Goal**: two committed, in-repo documents make the design provably researched and produce a prioritized security agenda.

**Independent Test**: documents exist in `docs/`, each of the 3 reference repos has explicit adopt/adapt/reject entries per pattern, and every recommendation cites a named source (tempest pattern or feature-001 finding).

### Implementation for User Story 3

- [x] T023 [US3] Write `docs/tempest-concorde-analysis.md`: summarized fundamentals of `fedora-bootc-pi`, `fw-os`, `fw-cicd` (base choices, materialization, secret handling, CI supply-chain controls) and, per pattern, an **adopt / adapt / reject** decision for this repo with rationale tied to `research.md` decisions D1–D10; includes the explicit deferred list (cosign/signing, Trivy gate, GH Actions reuse, Hummingbird base) with target conditions to adopt later.
- [x] T024 [US3] Write `docs/security-recommendations.md`: prioritized P1/P2/P3 actions where every item traces to (a) a `tempest-concorde` pattern or (b) a feature-001 finding with the artifact citation — must include the NVIDIA strategy block (rpmfusion open-modules for kernel modules + CUDA-repo userland with documented pin; CDI `nvidia-ctk`; Secure Boot MOK runbook), the 86 empty-vendor RPM enumeration action, the unresolved `:80`/`:9090`/`:9100` listeners, Ollama `*:11434` bind hardening, `tailscale-cockpit-certs.service` failure, IOMMU/VT-d enablement, and the feature-001 repo-artifact removals (`cuda-install.sh`, `install-gcc-13.yaml`, `scripts/granite-20.sh`).
- [ ] T025 [US3] Review pass on both docs: links to `state/` artifacts are descriptive references, not dependencies (state/ is git-ignored); markdown structure lint-clean; both files staged for commit alongside the pipeline code (they ARE committed — contrast with run artifacts).

**Checkpoint**: FR-010/FR-011 satisfied; SC-005 coverage 3/3 repos + every recommendation cited.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: lint, acceptance, regression, and reproducibility evidence; govern the spec status.

- [ ] T026 [P] Lint gate: `bash -n scripts/pipeline.sh scripts/hardening-verify.sh scripts/lib/pipeline-lib.sh` (and `shellcheck` if installed — else record the gap); zero errors.
- [ ] T027 Run the full quickstart (`specs/002-hardened-bootc-pipeline/quickstart.md` Q0–Q8) after all stories complete; append each Q result verbatim into `state/donnager-linux-<date>.pipeline-acceptance.md`.
- [ ] T028 [P] Host regression (SC-007): run `scripts/capture-state.sh`, diff-scan the fresh capture vs `state/donnager-linux-20260923.md` for any NEW unexplained listeners, NEW failed services, or NEW host packages outside the permitted set (podman images, pipeline artifacts); record verdict in acceptance file.
- [ ] T029 [P] Reproducibility (SC-006): run `make pipeline VM_NAME=f44-hardened-repro-test`, compare built image digest to the acceptance run's digest (must be equal), then `make clean VM_NAME=f44-hardened-repro-test` with confirm; record digest equality proof in acceptance file.
- [ ] T030 Update `specs/002-hardened-bootc-pipeline/spec.md` Status `Draft` → `Implemented`; mark every task `[x]` in this file; do not commit `state/` (ignored); leave repo-code commits to the user per constitution PR workflow.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies; T002–T004 parallel after T001 restores SSH.
- **Foundational (Phase 2)**: depends on Setup (T004's digests must exist before T005/T012); BLOCKS all stories.
- **US1 (Phase 3)**: depends on Foundational only.
- **US2 (Phase 4)**: depends on T008 skeleton + T010 checklist (Foundational) for engine constructs; logically validated against US1's pipeline but tasks T019–T020 can proceed in parallel with Phase 3.
- **US3 (Phase 5)**: depends on `research.md` (done); parallel with US1/US2 if capacity allows.
- **Polish (Phase 6)**: depends on US1 + US2 (T027, T028, T029 need a working gated pipeline).

### Within Each Story

- US1: T011→T012→T013→T014; T015→T016 (validate needs smoke-VM machinery from lib); T017 after T014/T015/T016; T018 last.
- US2: T019∥T020 → T021 (needs pipeline + fixtures + engine) → T022.
- US3: T023 → T024 → T025, sequential (recommendations consume analysis conclusions).

### Parallel Opportunities

- T002 ∥ T003 ∥ T004 (independent live verifications).
- T005 ∥ T006 ∥ T010 (different files; Containerfile, config template, checklist).
- T019 ∥ T020 (fixtures vs engine implementation).
- US3's T023 ∥ Phase 3 pipeline work (docs are independent of pipeline execution).
- T028 ∥ T029 in Polish (different evidence targets).

---

## Parallel Example: Setup

```bash
# After T001 restores SSH connectivity, run in parallel:
Task: "Q0.1 dnf group info evidence"
Task: "Q0.2 rpmfusion nvidia matrix evidence"
Task: "Pin base+builder digests into bootc/variables.env"
```

## Parallel Example: User Story 2

```bash
# Run together before T021's gate proof:
Task: "Create broken/healthy fixture set"
Task: "Implement all automatable H-checks in hardening-verify.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 (unblock SSH + pin digests) and Phase 2 (Containerfile, config template, scripts, checklist)
2. Phase 3 through T018 — hardened VM released end-to-end
3. **STOP and VALIDATE**: login prompt, key-only ssh, `bootc status` reference check

### Incremental Delivery

1. Setup + Foundational → skeleton + checklist exist
2. US1 → hardened VM exists (MVP)
3. US2 → checklist proven fail-closed as release gate
4. US3 → analysis + recommendations committed
5. Polish → acceptance, regression, reproducibility evidence complete

---

## Notes

- [P] tasks touch different files; story-tagged tasks belong to that story's phase only.
- No test framework introduced; US2 fixture tasks act as the negative/positive acceptance tests mandated by the spec.
- Everything the pipeline writes at runtime lands in git-ignored `state/`; only `docs/*.md`, Makefile, scripts, Containerfile, variables.env, config template, and the checklists/hardening.md are committed artifacts.
