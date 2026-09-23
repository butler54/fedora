# tempest-concorde Reference Analysis

**Feature**: 002-hardened-bootc-pipeline | **Date**: 2026-09-23

Fundamental analysis of the three reference repositories and what this project takes
from each. Ground truth for these claims: `specs/002-hardened-bootc-pipeline/research.md`
Part A (repos examined 2026-09-23).

## Repository summaries

### `tempest-concorde/fedora-bootc-pi`

Headless Fedora bootc image for Raspberry Pi (ARM64). Base is Fedora Hummingbird
(zero-CVE target, ARK kernel, read-only root) layered over `fedora-bootc:42`.
Deliverables produced locally with `bootc-image-builder` driven by a
`gomplate`-rendered `config.toml.tmpl`; secrets never enter git. GitHub Actions
build the image on ARM runners and push to Quay. Published container uses
Quadlet for a Node Exporter sidecar; sshd key-only with root as the only user.
Includes `containers-policy/` signature policy content and semantic-release
tooling.

### `tempest-concorde/fw-os`

Layer-2 application OS built **FROM** fedora-bootc-pi for an LED display
controller. Establishes the two-layer composition pattern (platform layer → app
layer). Notable techniques: `sysusers.d`/`tmpfiles.d`/`subuid` config files
baked into the image, rootless Quadlet units for its app container, podman
**secrets** provisioned by a dedicated bootstrap service (`fw-app-secrets.*`),
`bootc switch` as the deployment cut-over with built-in rollback, and a daily
cert-renewal timer. Proves rootless podman + Quadlet as the workload substrate,
not host-level services.

### `tempest-concorde/fw-cicd`

Shared GitHub Actions: `build-container`, `build-bootc`, `cosign-sign-verify`,
`commitlint`, `merge-manifest`, `sbom-attest`, `semantic-release`. Implements a
strict supply-chain posture: actions pinned by SHA, base images pinned by digest,
cosign signing (keyless via GitHub OIDC), CycloneDX SBOM generation +
attestation, Trivy gating on CRITICAL/HIGH, and SLSA L2–3 provenance via
`slsa-github-generator`.

## Decision matrix

### Adopt

| Pattern | From where | Where it lands here |
|---------|-----------|---------------------|
| Single `Makefile` facade over `scripts/` | all three | `Makefile` root targets → `scripts/pipeline.sh` |
| Digest-pinned base images | fw-cicd SLSA posture | `bootc/variables.env` pin + preflight drift check |
| `bootc-image-builder` materialization with gomplate config | fedora-bootc-pi, fw-os | `bootc/config.toml.tmpl` → QCOW2 |
| Secrets at pipeline time from env only | all three | `QUAY_*`, `SSH_PUBKEY`, `REGISTRY_PULL_SECRET` via env |
| Boot-time service preset via drop-in | fw-os sysusers/tmpfiles idiom | image-carried `90-hardened.preset` |
| `bootc upgrade` + timer as update model | fw-os docs | preset enables `bootc-fetch-apply-updates.timer` |
| Rootless/user-session execution only | fw-os rootless containers, feature-001 | user-session libvirt, no host mutation |
| commitlint + Conventional Commits | fw-cicd | already in repo (`commitlint.config.js`) |

### Adapt

| Pattern | Why adapted | Adaptation here |
|---------|-------------|-----------------|
| GH Actions reusable workflows (fw-cicd) | no CI runner budget in v1; pipeline is local-first | `scripts/pipeline.sh` local stages mirror their `build-bootc` flow; CI adoption is a deferred item (below) |
| cosign signing (fw-cicd) | v1 has no signing infrastructure; digest pinning covers the integrity chain record | deferred; digest recorded per run in `state/…pipeline-run.md` |
| Fedora Hummingbird base (fedora-bootc-pi) | zero-CVE base is attractive but high-commitment; the F44 container ecosystem is currently active for this project's GPU/desktop plans | stock `fedora-bootc:44` pinned; Hummingbird re-evaluated for the *host* image in a later feature |
| Quadlet sidecars (both) | VM is single-purpose; adding sidecars widens surface | no sidecars in v1; container workload model for lab VMs delivered via included podman |
| Trivy scanning (fw-cicd) | containerized scanner needs image pulls per run; host-install budget is zero | custom shell engine `scripts/hardening-verify.sh` against checklist items (v1); containerized Trivy as follow-up |

### Reject (not now / off-lane)

| Pattern | Why rejected here |
|---------|-------------------|
| ARM/RPi kickstart + WiFi plumbing | irrelevant to x86_64 QEMU/KVM guests |
| GUI/desktop package groups in VM image | violates minimal-surface intent (and spec's desktop-free baseline) |
| Tailscale inside the VM image | VM sits on host NAT; tailscale policy is a host/network-layer decision made per-deployment, not baked in |
| Interactive ISO installs | violates zero-interaction requirement (D3/D4, quickstart) |

## Deferred adoption list (tracked follow-ups)

| Item | Trigger to adopt |
|------|------------------|
| fw-cicd workflows end-to-end (build/push/sign/SBOM in CI) | when a real CI budget + runner exists; direct reuse of their reusable workflows expected |
| cosign signing of the produced image | with CI, or locally once a signing key story exists (recorded in security-recommendations) |
| Hummingbird-based hardened host image | after the VM pipeline matures (host currently mutable F44 — feature-001 provenance) |
| Containerized Trivy gate | alongside CI adoption |
| ANP/microsegmentation policy for lab VMs | when lab-VLAN network profiles (spec FR-006a futures) are implemented |
