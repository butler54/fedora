# Research: Hardened Fedora 44 bootc VM Pipeline

**Feature**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23

Phase 0 resolves all remaining unknowns, folds in the user's mid-plan directives
(package efficiency via bundles, current NVIDIA best-practice analysis), and
grounds every decision in the tempest-concorde reference analysis.

---

## Part A — tempest-concorde Reference Analysis (fundamental)

Direct examination of the three reference repositories on 2026-09-23.

### tempest-concorde/fedora-bootc-pi (37 commits)

**Pattern inventory**
- Headless bootc system, Makefile entry points (`make rpi5-img|iso|qcow`).
- Base: Fedora Hummingbird (zero-CVE target, ARK kernel, read-only root) layered on
  `quay.io/fedora/fedora-bootc:42`.
- Build outputs produced locally via `bootc-image-builder` driven from
  `config.toml.tmpl` + `gomplate`; secrets only live on the builder host.
- GitHub Actions build → push to Quay.io (ARM runners); semantic-release +
  commitlint; `containers-policy/` directory (image signature policy).
- Services: chronyd, tailscaled, sshd, NetworkManager + Node Exporter via Quadlet.
- SSH access: key-only, root only.
- SETUP-SECRETS.md and LOCAL-TESTING.md pattern: secrets documented, mechanics
  separated from the image.

### tempest-concorde/fw-os (39 commits)

**Pattern inventory**
- Layered OS on top of `fedora-bootc-pi` (`FROM <previous-layer>`) — composable
  base → app layer split.
- Quadlet-driven containers (`fw-app.container`, `fw-app.image`, rootless podman).
- `sysusers.d`, `tmpfiles.d`, `subuid-subgid.conf` as image-side config artifacts.
- Rootless podman secrets provisioning pattern (`podman secret create FW_*`) with
  a dedicated `fw-app-secrets.service` doing sync at boot.
- Deployment clientele: explicit user (`core`, UID 1000), groups for hardware ACLs.
- `bootc switch ghcr.io/...` used as the cut-over — layering step is real-world proven.
- Daily / on-boot cert-renew timer pattern.
- ISO path via `bootc-image-builder` + `gomplate` templated config (same idiom as pi repo).

### tempest-concorde/fw-cicd (39 commits)

**Pattern inventory**
- Reusable GitHub Actions workflows: `build-container`, `build-bootc`, `cosign-sign-verify`,
  `commitlint`, `merge-manifest`, `sbom-attest`, `semantic-release`.
- Supply-chain control set (SLSA L2–3): SHA-pinned actions, digest-pinned base images,
  cosign (keyless OIDC or key-based), CycloneDX SBOM + attestation, Trivy vuln gate
  (fail on CRITICAL/HIGH), hermetic runners, SLSA provenance via
  `slsa-github-generator`.

---

## Decisions

### D1 — Pipeline runtime shape

**Decision**: `make` facade → `scripts/pipeline.sh` (stages), `scripts/hardening-verify.sh`
(checklist engine), `scripts/lib/pipeline-lib.sh` (helpers). Authored locally; executes
against the lab host over BatchMode SSH, reusing feature-001's proven pattern.

**Rationale**: tempest-concorde uses `Makefile` as the user-visible entry + scripts
underneath (e.g., `tailscale-setup.sh`, `sync-fw-secrets.sh`). Make has no business
containing logic; scripts own behavior. SSH-off-host execution preserves FR-009
(zero host mutation) because all host-side effects live in podman and the user's
libvirt session — no new host packages required.

**Alternatives considered**: all-local builds on authoring machine (rejected — macOS
primary host and bib needs KVM-adjacent Linux podman); Ansible (rejected — heavier
than needed, adds runtime dep on host, same conclusion as feature-001 D1).

### D2 — Base image

**Decision**: `quay.io/fedora/fedora-bootc:44`, **pinned by digest**. Digest recorded
in `bootc/Containerfile` comment and in `bootc/variables.env` so the exact digest is
reviewable; pipeline hard-fails if digest drifts without an explicit bump commit.

**Rationale**: constitution P.III (supply-chain hygiene) + fw-cicd's "reproducibility
via digest." Fedora 44 matches the lab host's kernel/driver generation and the
container ecosystem we observed live (podman 5.8.7). Hummingbird (fedora-bootc-pi's
zero-CVE base) was evaluated but is ARM-oriented and adds a layer-stack commitment —
registered as a future candidate for the hardened host image, not this VM.

**Alternatives considered**: Hummingbird base (see above — deferred); Fedora 42
matching the old host image (rejected — user explicitly flagged F42-era decisions as
outdated for NVIDIA; moving to F44 across the board).

### D3 — VM materialization

**Decision**: QCOW2 produced by `bootc-image-builder` (`quay.io/centos-bootc/bootc-image-builder`,
digest-pinned) running in podman **on the lab host** against the Containerfile→image
pushed to the registry. User-session libvirt (`qemu:///session`) consumes the volume.

**Rationale**: this is the exact tempest-concorde materialization pattern
(`make qcow` + `config.toml.tmpl` + `gomplate`). User-session libvirt was verified
working on the host during feature 001 (an inactive test domain already exists).
No host-level changes.

**Alternatives considered**: `bootc install to-existing-root` (rejected — mutates the
host expecting management); Fedora-Cloud-image + `bootc switch` (rejected — two-step;
bib does it in one and mirrors reference repos); anaconda ISO (rejected — interactive
install path violates the "no interactive provisioning" constraint).

### D4 — VM first-boot config

**Decision**: cloud-init absent; bib config (`config.toml.tmpl`) carries:
`customizations.user` (single user, locked password, ssh authorized_keys from
pipeline env), `customizations.services` (enable sshd + bootc-upgrade timer),
and kernel `append` arguments if needed. VM's bootc upgrade reference points at
the registry `REGISTRY_REF` so `bootc upgrade` inside the VM pulls future pushes.

**Rationale**: bib-native config (proven by reference repos) avoids a second
provisioning mechanism (cloud-init) and keeps everything repo-defined.

**Alternatives considered**: cloud-init (rejected — extra daemon in the attack
surface + another mechanism to secure); ignition (rejected — Fedora IoT/mainframe
oriented, unusual on x86 bootc guests and unsupported by bib defaults).

### D5 — Package efficiency policy (user directive)

**Decision**: the Containerfile MUST declare dnf **groups** ("bundles") instead of
individual packages wherever a group exists for the intent, and MUST NOT re-declare
packages already included in the chosen groups. A build-time lid (`dnf group info`
dump recorded in the execution record) proves what each group delivered. Groups are
resolved by dnf at build — so the image stays minimal and the manifest stays short.

**Rationale**: user requirement ("Don't declare a package if you can declare a
bundle") + image minimalism (reduced attack surface) + auditability (short manifest
is reviewable; group expansion is recorded per build).

**Implementation anchors (F44 groups, verified patterns)**:
- Core runtime: implicit in `fedora-bootc:44` base — DO NOT redeclare.
- Server baseline: `@core` is implied; explicitly consider `@standard` only if a
  tool class (e.g., firewalld-plus) is strictly required and not already in base.
- Container workload support: `@container-management` (podman, buildah, skopeo,
  runc, containernetworking-plugins) instead of individual installs.
- Virtualization tooling inside the VM: NOT installed (the VM is a guest, not a
  hypervisor — keeps image minimal).
- Diagnostic set: if required, use individual packages only for tools with no
  group (`iproute`/`iputils`/`procps-ng`/`ss`-providers are already in base F44 —
  verify at lid step).

**Build-time verification (recorded per run)**: `dnf group info <group>` output
dumped to the execution record; the pipeline fails if a declared group resolves to
zero packages or a declared package is already inside a declared group (duplicate
declaration check).

**Alternatives considered**: individual package lists (rejected by user directive);
full workstation groups (rejected — GUI surface contradicts locked-down aim).

### D6 — NVIDIA driver best-practice (user directive — thorough analysis)

**Decision (for this feature's VM image)**: **no NVIDIA components in the VM image**.
GPU/VFIO is out of scope per spec assumptions. The analysis below is captured here
because the user asked for it to inform decisions; its actionable output lands in
`docs/security-recommendations.md` for the *host* and future host-image work.

**Analysis (grounded in 2026 NVIDIA/Fedora landscape + feature-001 host evidence)**:

1. **Driver packaging split (current best practice)**:
   NVIDIA ships three kernel-module flavors: proprietary (legacy), `nvidia-open`
   (open kernel modules, GPU System Processor firmware), and nouveau (out of scope).
   Since driver 560-series, **open kernel modules are the recommended default for
   Turing+ GPUs** (RTX 20/30/40); with the R580 branch the proprietary kernel module
   is deprecated for Turing/Ampere/Ada/Blackwell — open is required there. The
   host's RTX 4080 SUPER (Ada) therefore sits squarely in the open-modules lane.
2. **Where the host's current state sits**: driver `615.71.09` from the NVIDIA CUDA
   repository, 86 `(none)`-vendor RPMs including `cuda-* 13.4` packages and
   `nvidia-container-toolkit`. This works (nvidia-smi valid) but creates two RPM
   universes (Fedora/RPMFusion vs CUDA repo) with independent cadence — drift risk,
   and feature-001 flagged it for enumeration.
3. **rpmfusion path (Fedora-idiomatic)**: `akmod-nvidia-open` + `kmod-nvidia-open`
   with MOK-signed modules under Secure Boot (same MOK flow already used on the
   host for akmods). rpmfusion F44 branch provides the 575/580-series line. This
   aligns with Fedora packaging norms, signs consistently with Secure Boot, and
   keeps the driver in the same lifecycle cadence as the OS.
4. **CUDA-repo path (what today uses)**: appropriate when exact CUDA toolkit +
   driver pairs matter (deep-learning toolchains that pin to specific CUDA
   versions, e.g., cuda-13.4 observed). It is best practice to let the CUDA repo
   own the **userland** (toolkit, `cuda-cudart`, `nvidia-container-toolkit`)
   even when the kernel modules come from rpmfusion — pinning is done via dnf
   priorities/versionlock, documented, not ad-hoc.
5. **Container GPU access best practice**: CDI (Container Device Interface) via
   `nvidia-ctk cdi generate` — host already has `libnvidia-container1` and
   `nvidia-container-toolkit` installed. Podman ≥5 supports `--device
   nvidia.com/gpu=all` natively. This is the modern path (supersedes the legacy
   `nvidia-container-runtime` hook and matches ramalama/ollama observed in the
   feature-001 network findings).
6. **Secure Boot interplay**: MOK enrollment + `akmods --force` rebuild +
   `dracut --regenerate-all` remains required on first install or driver-major
   changes; `bootctl status` + `mokutil --sb-state` verified OK on host.
   `rd.driver.blacklist=nouveau,nova_core` on kernel cmdline (observed) is correct
   and must be mirrored in any future host-image Containerfile.
7. **Desktops vs headless**: Wayland + NVIDIA works on current drivers; for the
   *VM* (no GPU) `virtio-gpu`/QXL with `modeset` only — no NVIDIA anything.

**Decision captured as recommendations (land in `docs/security-recommendations.md`,
FR-011)**: consolidate host driver sourcing (rpmfusion kernel modules + CUDA-repo
userland with documented pin), adopt CDI explicitly for GPU-in-container, and
encode the Secure Boot MOK runbook in `docs/` (migrating `nvidia-driver.md`'s valid
content per feature-001 review).

**Alternatives considered**: keep CUDA-repo driver wholesale (rejected as
long-term recommendation — fragmented lifecycle, drift-prone); switch to nouveau
(rejected — Ada support immature for CUDA/LLM workloads).

### D7 — Registry

**Decision**: private `quay.io` repository, parameter `REGISTRY_REF` defaulting to
`quay.io/<namespace>/hardened-f44:<tag>` (namespace recorded in
`bootc/variables.env`, **not** hardcoded). Auth: `QUAY_USER`/`QUAY_TOKEN` from the
pipeline environment (`podman login` on the lab host uses those env vars at
pipeline time; nothing persisted in-repo). VM pull secret is injected at VM-create
time into the VM's `/etc/ostree/auth.json` via bib `customizations` (file only
exists inside the VM disk on the LUKS-encrypted host).

**Rationale**: Q3 clarification (registry + `bootc upgrade` pull); constitution
secrets hygiene; quay.io is also the reference pattern (fedora-bootc-pi pushes to
Quay; fw-cicd pushes to ghcr — choice is orthogonal, quay chosen because bootc
upstream examples and Fedora's own images live there).

**Alternatives considered**: ghcr.io (viable — kept as parameter variation);
local registry on lab host (rejected for v1 — extra service to harden and
maintain).

### D8 — Checklist engine

**Decision**: `scripts/hardening-verify.sh` — deterministic shell assertions, one
function per checklist item ID (e.g., `H001..H0NN`) sourced against
`specs/002-hardened-bootc-pipeline/checklists/hardening.md`. Runs twice per
pipeline: once against the built image in a throwaway podman container (static
assertions: file permissions, sshd_config, systemd presets), and once against the
booted VM over ssh (runtime assertions: listening sockets, SELinux mode, timer
enabled). Any non-zero item fails the run (fail-closed).

**Rationale**: FR-003 + US2 acceptance; shell assertions are inspectable and
mirror feature-001's auditability principle; Trivy-style external scanner was
evaluated (fw-cicd pattern) but adds a tooling dependency with zero host install
budget — recorded as a follow-up, containerized variant possible later.

**Alternatives considered**: OpenSCAP profile (rejected for v1 — heavyweight,
needs tailoring for bootc image lifecycle; noted in recommendations doc as future
candidate); containerized Trivy (deferred follow-up).

### D9 — Execution record

**Decision**: each run writes `state/donnager-linux-<date>.pipeline-run.md`
(git-ignored) with: repo commit, builder/base/built image digests, group-expansion
lid output, registry ref pushed, checklist matrix, VM domain, durations per stage.

**Rationale**: FR-007 + feature-001 convention; machine-greppable, reviewable
side-by-side with the state-capture artifacts.

### D10 — Analysis document homes

**Decision**: `docs/tempest-concorde-analysis.md` and
`docs/security-recommendations.md`, committed (FR-010/FR-011). The hardening
checklist lives at `specs/002-hardened-bootc-pipeline/checklists/hardening.md`
(FR-012) — keeps checklists inside the spec feature directory, consistent with
feature-001's requirements-checklist location.

**Rationale**: constitution requires discoverable docs from repo root; spec-kit
checklists stay inside their feature directory.

---

## Pending live verifications (implementation-phase blockers tracked here)

These require SSH to `chris@donnager-linux` whose agent-held identity expired
mid-session (YubiKey-backed key absent from ssh-agent). They do NOT block plan
approval; they gate the listed tasks:

- `dnf group info` snapshots for groups chosen in D5 (records exact bundle
  membership at pin time).
- rpmfusion F44 availability matrix for `akmod-nvidia-open`/`kmod-nvidia-open`
  (validates D6 recommendation wording with live version numbers).
- Verification that `quay.io/fedora/fedora-bootc:44` digest at pin time resolves
  identically from the lab host (`skopeo inspect --no-tags docker://...`).

All are appended to `quickstart.md` Q-series acceptance steps.
