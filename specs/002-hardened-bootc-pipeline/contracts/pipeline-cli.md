# Contract: Pipeline CLI

**Feature**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23

## Purpose

Single documented entry point for the hardened-VM pipeline (spec FR-002). `make` is a
facade; behavior lives in `scripts/pipeline.sh`.

## Surface

```
make pipeline [HOST=chris@donnager-linux] [REGISTRY_REF=quay.io/<ns>/hardened-f44:latest] \
              [VM_NAME=f44-hardened-<run_id>] [VCPUS=4] [MEMORY_MIB=8192] [DISK_GIB=60] \
              [NETWORK_PROFILE=nat-user-session]
```

Sub-targets (debug/introspection only; `pipeline` always runs the full sequence):

| Target | Script stage(s) |
|--------|-----------------|
| `make build` | build image from `bootc/Containerfile` |
| `make validate` | run `scripts/hardening-verify.sh` against built image |
| `make push` | digest-capture + registry push |
| `make vm` | bib qcow2 create + libvirt define/start |
| `make clean` | destroy VM + delete run's qcow2 (interactive confirm) |

Direct script invocation is equally supported and identical:

```
scripts/pipeline.sh [--host …] [--registry-ref …] [--vm-name …] [--vcpus …] \
                    [--memory-mib …] [--disk-gib …] [--network-profile …] \
                    [--dry-run] [--help]
```

## Stage sequence (fixed order)

1. `preflight` — ssh probe, `state/` git-ignore check, disk headroom check (recorded
   requirement: ≥ 40 GiB free in VM volume area), digest pin verification (D2).
2. `build` — `podman build` on lab host from `bootc/Containerfile`; lid passes
   (D5 duplicate-declaration check; group-expansion dump).
3. `scan` — static hardening engine run against the image in a throwaway container.
4. `validate` — runtime hardening engine run against a smoke-booted VM (short-lived).
   The smoke VM is destroyed before release continues.
5. `push` — pushed to `REGISTRY_REF`; digest recorded.
6. `vm` — bootc-image-builder produces QCOW2 referencing `REGISTRY_REF`; user-session
   libvirt defines dom `<VM_NAME>` (collision = hard error) and starts it.

Any stage failure ⇒ pipeline exit non-zero, execution record shows `failed`, no ready
VM left (FR-003, FR-007a).

## Parameters

| Name | Default | Notes |
|------|---------|-------|
| HOST | `chris@donnager-linux` | BatchMode SSH must already work |
| REGISTRY_REF | from `bootc/variables.env` | private repo assumed (D7) |
| VM_NAME | `f44-hardened-<run_id>` | existing domain = collision error |
| VCPUS | 4 | |
| MEMORY_MIB | 8192 | |
| DISK_GIB | 60 | |
| NETWORK_PROFILE | `nat-user-session` | v1 only; parameter seam per FR-006a |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | released; VM defined+started; record written |
| 1 | usage error |
| 2 | preflight failure (ssh, git-ignore, disk, digest pin) |
| 3 | build failure |
| 4 | hardening gate failure (any checklist item FAIL) |
| 5 | push failure (registry) |
| 6 | VM creation failure |
| 7 | collision (existing domain / volume) |

## Environment (secrets)

| Var | Purpose |
|-----|---------|
| QUAY_USER / QUAY_TOKEN | registry push credentials at pipeline time (host env; never repo or image) |
| SSH_AUTH_SOCK | key source; BatchMode enforced |

## Outputs

- `state/donnager-linux-<YYYYMMDD>.pipeline-run.md` — execution record (schema in
  `contracts/execution-record.md`).
- VM domain `<VM_NAME>` in user-session libvirt, reachable on NAT address via
  `virsh domifaddr`.
- Pushed image at `REGISTRY_REF` with recorded digest.
