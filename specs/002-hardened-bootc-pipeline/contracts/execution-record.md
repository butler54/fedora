# Contract: Pipeline Execution Record

**Feature**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23

## Artifact

`state/donnager-linux-<YYYYMMDD>.pipeline-run.md` — git-ignored (feature-001 `state/`
convention). One file per day; multiple runs append as sections separated by `---`.

## Per-run block schema

```
## Run <run_id: YYYYMMDD-HHMMSS>

- Repo commit: <short sha>
- Stage durations: preflight=<s> build=<s> scan=<s> validate=<s> push=<s> vm=<s>
- Result: released | failed

### Images

| Role | Reference | Digest |
|------|-----------|--------|
| base | quay.io/fedora/fedora-bootc:44 | sha256:… |
| builder | quay.io/centos-bootc/bootc-image-builder:… | sha256:… |
| built | <REGISTRY_REF>@<digest> | sha256:… |

### Bundle manifest (lid)

<verbatim `dnf group info` output per declared group + package-in-group duplicate
check result>

### Hardening verdicts

| Item | Phase | Result | Evidence |
|------|-------|--------|----------|
| H001 | image | PASS/FAIL | … |

### VM

- Domain: <name or null>
- vcpus / memory / disk: <values>
- network profile: nat-user-session
- bootc reference: <REGISTRY_REF>
- Reachable address (NAT): <address or null>

### Notes

<free text — stage failures, anomalies, manual steps taken>
```

## Invariants

- `released` records MUST contain a VM section with a non-null domain and digests
  present for base+built images.
- `failed` records MUST name the failing stage in the Notes section.
- A record must never contain credentials, tokens, or ssh private key material —
  digests and public key fingerprints only.
