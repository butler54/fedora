# Hardening Checklist: Hardened Fedora 44 bootc VM Pipeline

**Purpose**: Machine-verifiable lockdown controls every pipeline run gates on (spec FR-012).
**Created**: 2026-09-23
**Engine**: `scripts/hardening-verify.sh`
**Contract**: `contracts/hardening-checklist.md` (schema + gate semantics)

## Baseline admitted listener set (H014 comparison reference)

| Listener | Justification |
|----------|---------------|
| tcp/22 (sshd) | pre-authorized baseline (spec clarification Q1) |

Changes to this set require a commit to this checklist (governance artifact).

---

### H001 Base image pinned by digest

- **Pillar**: build
- **Automatable**: yes
- **Check**: `grep -qE '^FROM .+@sha256:[0-9a-f]{64}' bootc/Containerfile`
- **Evidence**: FROM line contains sha256 digest
- **Failure policy**: fail-closed

### H002 No secrets in build context

- **Pillar**: build
- **Automatable**: yes
- **Check**: scan `bootc/` for private-key/token patterns (`BEGIN .* PRIVATE KEY`, `tskey-auth`, `quay.io.*:.*@`); zero hits
- **Evidence**: grep returns nothing
- **Failure policy**: fail-closed

### H003 Image builds reproducibly

- **Pillar**: build
- **Automatable**: yes
- **Check**: pipeline builds twice on unchanged tree and reports identical digest (executed in polish, recorded in acceptance file)
- **Evidence**: equal digests across two runs
- **Failure policy**: fail-closed

### H004 No package-in-group duplicate declarations

- **Pillar**: build
- **Automatable**: yes
- **Check**: `scripts/pipeline.sh` lid pass (`lid_check`) — passes with no duplicates emitted
- **Evidence**: lid log line `[lid] OK`
- **Failure policy**: fail-closed

### H010 sshd password auth disabled

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `sshd -T | grep -E '^passwordauthentication no$'`
- **Evidence**: effective sshd config shows no
- **Failure policy**: fail-closed

### H011 sshd root login restricted

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `sshd -T | grep -E '^permitrootlogin (prohibit-password|no)$'`
- **Evidence**: root login not password-allowed
- **Failure policy**: fail-closed

### H012 SELinux Enforcing

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `getenforce` == `Enforcing`
- **Evidence**: stdout `Enforcing`
- **Failure policy**: fail-closed

### H013 Firewall default-deny inbound with tcp/22 only exception

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `firewall-cmd --get-default-zone` is a deny-by-default zone or firewalld-replaced nftables default-drop; AND `firewall-cmd --list-ports` ∩ allowed-set ⊆ {22/tcp}
- **Evidence**: default zone FedoraWorkstation (drop-inbound) and ports list only 22/tcp or empty
- **Failure policy**: fail-closed

### H014 No listeners beyond admitted set

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `ss -tulnH | awk '{print $5}' | grep -E '(0\.0\.0\.0|\*|\[::\])'` results ⊆ {`:22`}
- **Evidence**: only port 22 externally bound
- **Failure policy**: fail-closed

### H015 sshd drop-in ownership and mode

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `stat -c '%U:%G %a' /etc/ssh/sshd_config.d/50-hardened.conf` == `root:root 644`
- **Evidence**: exact stat output
- **Failure policy**: fail-closed

### H020 bootc upgrade timer enabled

- **Pillar**: updates
- **Automatable**: yes
- **Check**: `systemctl is-enabled bootc-fetch-apply-updates.timer` == `enabled`
- **Evidence**: `enabled`
- **Failure policy**: fail-closed

### H021 Upgrade reference points at pipeline registry

- **Pillar**: updates
- **Automatable**: yes
- **Check**: `bootc status --format yaml` (or `bootc status`) image reference == `REGISTRY_REF` recorded in run record
- **Evidence**: references equal
- **Failure policy**: fail-closed

### H022 No default/unlocked password accounts

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `passwd -S <image-user>` status ∈ {`L`, locked}; no account field equal `NP`
- **Evidence**: locked password field for user
- **Failure policy**: fail-closed

### H030 Execution record produced

- **Pillar**: build
- **Automatable**: yes
- **Check**: `state/<hosttag>-<date>.pipeline-run.md` exists, contains the run id, and digests for base+built images
- **Evidence**: file + contents
- **Failure policy**: fail-closed

### H031 VM domain is user-session only

- **Pillar**: runtime
- **Automatable**: yes
- **Check**: `virsh -c qemu:///system list --all --name` contains no `f44-hardened-*` entry AND domain exists under `qemu:///session`
- **Evidence**: empty system-session match
- **Failure policy**: fail-closed

### H040 VM-level disk encryption decision (documented exception)

- **Pillar**: runtime
- **Automatable**: no
- **Evidence**: spec decision — VM volumes reside on host LUKS (observed feature-001); VM-level dm-crypt deferred with rationale. Rationale present in `docs/security-recommendations.md`.
- **Owner**: chris
- **Failure policy**: fail-closed (blocks release pending owner sign-off recorded in acceptance file)

### H041 Secure Boot inside guest

- **Pillar**: runtime
- **Automatable**: no
- **Evidence**: enablement depends on libvirt UEFI/secboot support at release time; verified manually via `bootctl status` inside VM when enabled, or documented as deferred with date
- **Owner**: chris
- **Failure policy**: fail-closed (documents current status in acceptance file)
