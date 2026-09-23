# Security Recommendations

**Feature**: 002-hardened-bootc-pipeline | **Date**: 2026-09-23

Prioritized actions flowing from (a) the tempest-concorde analysis and (b) the
feature-001 live-state capture of `donnager-linux` (artifact:
`state/donnager-linux-20260923.md` — uncommitted, git-ignored). Priorities:
**P1** = do before/at host migration; **P2** = do with the next image iteration;
**P3** = hardening roadmap.

---

## P1

### 1. Consolidate NVIDIA driver sourcing on the host

**Trace**: feature-001 Packages findings — 86 `(none)`-vendor RPMs (CUDA repo),
NVIDIA driver 615.71.09 from the CUDA repo, `akmods` present but `kmod-nvidia`
absent. Research D6 (live-verified 2026-09-23): rpmfusion F44 ships
`akmod-nvidia-open 3:615.71.09-1.fc44` — same driver generation, Fedora-idiomatic
packaging, and Secure Boot MOK signing through the akmods flow the host already
uses.

**Action**: move kernel modules to `akmod-nvidia-open`/`kmod-nvidia-open` from
rpmfusion; keep CUDA-repo userland (toolkit, `cuda-cudart`, etc.) pinned via dnf
versionlock or module priorities for LLM-workload compatibility. Rationale:
single-cadence kernel-module lifecycle aligned with kernel updates; eliminates
the two-universe drift between 21 RPMFusion pkgs and 86 vendorless CUDA pkgs
surfacing as layer-cake breakage during the bootc host migration.

### 2. Adopt CDI explicitly for GPU-in-container on the host

**Trace**: feature-001 — `libnvidia-container1`, `nvidia-container-toolkit`
already installed; Ollama exposed on `*:11434`.

**Action**: generate and manage the CDI spec (`nvidia-ctk cdi generate`) as a
host runbook step in `docs/`; use `podman --device nvidia.com/gpu=all` rather
than legacy hooks; then bind the Ollama listener to localhost or tailscale0
(finds its way into the host-image Containerfile/quadlet for the LLM role).

### 3. Close or explain the unaccounted listeners on the host

**Trace**: feature-001 Network findings — unexplained `*:80`, `*:9090`, `*:9100`.

**Action**: identify owner processes (feature-001 reviewer note) and either
document each in the hardened host image or remove them in the `001-capture`
follow-up migrations. Items carrying `investigate` in the feature-001 report MUST
be resolved before host-day-one cut-over.

### 4. Enumerate the 86 `(none)`-vendor RPMs before host image definition

**Trace**: feature-001 Packages findings.

**Action**: produce the explicit list in the migration spec (feature 003) with
each item marked migrate/remove/keep. The host bootc image is defined once this
list is resolved — otherwise unknown unsigned/unmanaged software drags into the
locked-down image.

---

## P2

### 5. Adopt fw-cicd's supply-chain controls for this pipeline

**Trace**: `docs/tempest-concorde-analysis.md` deferred list.

**Action**: when CI exists, consume `tempest-concorde/fw-cicd` reusable
workflows: build → Trivy scan (gate CRITICAL/HIGH) → SBOM (CycloneDX) → cosign
sign → push. The local pipeline already enforces digest pinning (prelude to this);
CI adds attestation and public verifiability.

### 6. Enable IOMMU/VT-d on the host for the lab role

**Trace**: feature-001 Host Context findings — `/sys/kernel/iommu_groups` empty;
kernel cmdline lacks `intel_iommu=on`.

**Action**: BIOS check (VT-d/VT-x-d) + kernel argument via the future host
bootc image (`bootc host` config or kargs via image). Unblocks GPU-passthrough
variants of this pipeline (profile `vlan-gpu` in the FR-006a seam).

### 7. Clean failed and orphaned units

**Trace**: feature-001 Services findings — `tailscale-cockpit-certs.service`
failed.

**Action**: resolve or disable pre-migration; if cockpit stays, fold cert issuance
into the host image. VM-side equivalent: keep the hardenedVM image unit-clean
(the 002 checklist's future H-items should fail on `--failed` units post-boot).

### 8. Retire superseded repo artifacts

**Trace**: feature-001 Repo Artifacts table — dispositions recorded:

- remove: `install-gcc-13.yaml`, `cuda-install.sh`, `scripts/granite-20.sh`
- migrate: `nvidia-driver.md` (valid Secure Boot/LUKS content → `docs/`),
  `hard-to-automate.md`
- investigate: `installer.yaml`, `inventory.yaml`, `requirements.txt`,
  `pyproject.toml`, `thunderbird.md`

**Action**: execute removals/migrations after the host-state investigation items
(P1.3, P1.4) resolve, as one cleanup PR.

---

## P3

### 9. Move to signed pipeline artifacts

**Trace**: tempest-concorde analysis deferred list.

**Action**: cosign (keyless via OIDC once CI exists) for the hardened-f44 image;
record verification instructions in quickstart; add a checklist item H032
"signature verifiable" once available.

### 10. Evaluate Fedora Hummingbird as hardened host base

**Trace**: `fedora-bootc-pi` pattern (zero-CVE target, read-only root, ARK kernel).

**Action**: assess Hummingbird for the eventual *host* bootc image once F44 VM
operations are routine; map "zero-CVE target" implications on the GPU/CUDA
tensor stack before committing.

### 11. Network profiles for lab scenarios

**Trace**: clarification Q2 (spec) — mix of internet-connected and isolated
networks anticipated.

**Action**: implement `vlan-bridge` and `isolated` profiles via the FR-006a
parameter seam once SC/acceptance of the NAT profile is green; guard the
`vlan-bridge` profile with an explicit runbook (VLAN 200–203 fabric is BGP-routed
on this host — feature-001 Network).

### 12. VM-level encryption when VM data becomes sensitive

**Trace**: spec assumption (v1: no VM LUKS, host LUKS rationale) + checklist H040.

**Action**: revisit when VMs store credentials or models with usage data; then
switch bib config to LUKS rootfs or encrypt a dedicated data volume per VM.
