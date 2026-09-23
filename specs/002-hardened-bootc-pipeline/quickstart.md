# Quickstart: Hardened Fedora 44 bootc VM Pipeline

**Feature**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23

Runnable validation scenarios proving the feature works end-to-end. Assumes the
implementation in `tasks.md` has been executed.

## Prerequisites

- SSH to `chris@donnager-linux` works non-interactively (BatchMode) — see Note A below.
- This repository checked out at the commit under test; working tree may be dirty
  (uncommitted is fine — pipeline records the commit, not the tree).
- `QUAY_USER`/`QUAY_TOKEN` exported for the registry push stage.
- Lab host has ≥ 40 GiB free in the VM volume area (quickstart Q0 verifies).

### Note A — SSH agent state

During planning, the agent-held identity for `donnager-linux` expired (YubiKey-backed
key absent from `ssh-agent`). Before any stage executes, re-register the identity,
e.g. `ssh-add` with the appropriate key. The pipeline's preflight step fails fast
(exit 2) if BatchMode SSH does not silently authenticate.

## Q0 — Live verifications deferred from planning

These close the "pending live verifications" tracked in `research.md`:

```
# 0.1 Bundle membership snapshot (evidence for D5 lid)
ssh chris@donnager-linux 'dnf group info container-management 2>/dev/null | head -40'
# Expected: group exists, lists podman/buildah/skopeo members

# 0.2 rpmfusion F44 NVIDIA matrix (evidence for D6 recommendations)
ssh chris@donnager-linux 'dnf list --available "akmod-nvidia*" "kmod-nvidia*" 2>/dev/null | tail -10'
# Expected: akmod-nvidia-open / kmod-nvidia-open present in rpmfusion F44 repos

# 0.3 Base digest pin check (evidence for D2)
ssh chris@donnager-linux 'skopeo inspect docker://quay.io/fedora/fedora-bootc:44 2>/dev/null | sha256sum || podman image inspect quay.io/fedora/fedora-bootc:44 --format "{{.Digest}}"'
# Expected: digest matches bootc/variables.env BASE_DIGEST
```

## Q1 — Static gates

```
bash -n scripts/pipeline.sh scripts/hardening-verify.sh scripts/lib/pipeline-lib.sh && echo bash-ok
# shellcheck absence is the known dev-tool gap (feature-001 note)
scripts/pipeline.sh --dry-run
# Expected: stage list + parameters printed; no mutations; exit 0
```

## Q2 — Fail-closed checklist proof (US2 acceptance)

```
# Seed a broken fixture: hardening engine must FAIL closed on a deliberately
# non-compliant image fixture
scripts/hardening-verify.sh --against fixture:broken
echo $?   # Expected: non-zero

# Control run
scripts/hardening-verify.sh --against fixture:healthy
echo $?   # Expected: 0
```

## Q3 — Full pipeline run (US1 acceptance)

```
make pipeline RUN_NOTES="first acceptance run"
echo $?                    # Expected: 0
ls state/                  # Expected: *.pipeline-run.md for today
```

## Q4 — VM validation

```
# reaches login prompt (SC-002) — observe with virsh console during first boot
ssh chris@donnager-linux 'virsh domifaddr f44-hardened-* --source agent 2>/dev/null || virsh domifaddr f44-hardened-*'
# Expected: NAT address listed
ssh chris@donnager-linux 'timeout 120 bash -c "until virsh guestvainfo f44-hardened-* >/dev/null 2>&1; do sleep 5; done" && echo guest-agent-ok' || true
# key-only ssh check from the lab host side
ssh chris@donnager-linux 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new chris@$(virsh domifaddr f44-hardened-* --source arp | awk "/ipv4/{print \$4}" | cut -d/ -f1) true' 
# Expected: succeeds via authorized key; password path impossible (BatchMode)
```

## Q5 — Listener audit (SC-004)

```
ssh chris@donnager-linux 'VMIP=$(virsh domifaddr f44-hardened-* --source arp | awk "/ipv4/{print \$4}" | cut -d/ -f1); \
  ssh -o BatchMode=yes chris@$VMIP "ss -tulnH | awk \"{print \\\$5}\" | grep -E \"(0\\\\.0\\\\.0\\\\.0|\\\\*|\\\\[::\\\\])\" | sort -u"'
# Expected output equal exactly to the admitted listener set in the checklist:
#   0.0.0.0:22  and/or  :::22   (sshd, pre-authorized)
```

## Q6 — Host regression check (SC-007)

```
scripts/capture-state.sh >/dev/null
git diff --no-index --stat state/donnager-linux-20260923.md state/donnager-linux-$(date -u +%Y%m%d).md || true
# Expected: no NEW unexplained listeners, no NEW failed services, no NEW host
# packages outside the allowed set (podman images, pipeline artefacts)
```

## Q7 — Reproducibility (SC-006)

```
make pipeline VM_NAME=f44-hardened-repro-test
grep -E 'built.*sha256' state/donnager-linux-$(date -u +%Y%m%d).pipeline-run.md | sort -u | wc -l
# Expected: one unique built digest across today's runs
make clean VM_NAME=f44-hardened-repro-test   # confirm prompt
```

## Q8 — Update loop (FR-005c / Q3 clarification)

```
# On the VM: bootc upgrade points at the registry ref pushed by the pipeline
ssh chris@donnager-linux 'VMIP=$(virsh domifaddr f44-hardened-* --source arp | awk "/ipv4/{print \$4}" | cut -d/ -f1); \
  ssh -o BatchMode=yes chris@$VMIP bootc status | head -20'
# Expected: spec. image reference == REGISTRY_REF from the pipeline run
ssh chris@donnager-linux 'VMIP=$(virsh domifaddr f44-hardened-* --source arp | awk "/ipv4/{print \$4}" | cut -d/ -f1); \
  ssh -o BatchMode=yes chris@$VMIP systemctl list-timers bootc-fetch-apply-updates.timer --no-pager || \
  ssh -o BatchMode=yes chris@$VMIP systemctl list-timers --no-pager | grep -i bootc'
# Expected: a bootc update timer is enabled with a next-run timestamp
```
