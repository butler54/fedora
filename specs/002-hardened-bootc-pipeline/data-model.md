# Data Model: Hardened Fedora 44 bootc VM Pipeline

**Feature**: `002-hardened-bootc-pipeline` | **Date**: 2026-09-23

## Entity: Image Definition

The declarative OS source. Lives in-repo, version-controlled.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| base_image_ref | string (docker ref) | yes | `quay.io/fedora/fedora-bootc:44` |
| base_digest | sha256 string | yes | pinned in `bootc/variables.env`; bump = explicit commit |
| group_manifest | list of dnf group names | yes | bundles only (D5); see `bootc/Containerfile` |
| package_manifest | list of package names | yes | only where no group exists (D5 constraint) |
| config_overlay | set of file templates | yes | `config.toml.tmpl`, systemd presets, sshd drop-ins |
| builder_image_ref | string + digest | yes | `quay.io/centos-bootc/bootc-image-builder:@sha256…` |

**Validation**
- No package in `package_manifest` may be a member of a group in `group_manifest`
  (pipeline lid check, hard error).
- `base_digest` must equal the digest recorded in the run's execution record for a
  clean run; drift requires an explicit commit.

## Entity: Pipeline Run

One end-to-end execution.

| Field | Type | Required |
|-------|------|----------|
| run_id | `YYYYMMDD-HHMMSS` UTC | yes |
| repo_commit | short sha | yes |
| base_digest_used | sha256 | yes |
| built_image_digest | sha256 | yes |
| registry_ref | string | yes |
| checklist_results | map[item_id → PASS/FAIL/raw] | yes |
| vm_domain | string or null | yes (null if run failed pre-VM) |
| stage_durations | map[stage → seconds] | yes |
| artifact_paths | list of state/* files | yes |

**Lifecycle**
```
queued → building → scanning → validating → pushing → creating-vm → released | failed
```
Any stage failure ⇒ `failed`, no VM in a "ready" state, pipeline exits non-zero.

## Entity: Hardening Checklist Item

One control in `specs/002-hardened-bootc-pipeline/checklists/hardening.md`.

| Field | Type | Required |
|-------|------|----------|
| item_id | `H###` | yes |
| title | string | yes |
| pillar | enum {`build`,`runtime`,`updates`} | yes | (spec FR-005 pillars)
| automatable | bool | yes |
| check_command | string (shell) or null | yes if automatable |
| evidence | string (what proves pass) | yes |
| owner | string | yes if manual-verify |
| failure_policy | enum {`fail-closed`} | yes — currently only fail-closed exists |

**Enumeration (initial set)** — concrete items defined in the checklist file itself:
H001 base digest pinned, H002 no secrets in build context, H003 image builds
reproducibly, H004 manifest contains no duplicate (group vs package) declarations,
H010 sshd key-only (PasswordAuthentication no), H011 sshd root login disabled,
H012 SELinux Enforcing, H013 firewall default-deny inbound with tcp/22 only,
H014 no listeners beyond checklist-enumerated set, H015 sshd drop-in owned and
mode 0644 root:root, H020 bootc upgrade timer enabled, H021 upgrade ref points
at pushed registry image, H022 no default passwords in image
(`passwd -S` null-check), H030 execution record written, H031 VM domain is
user-session only.

## Entity: Hardening Gate Verdict

Result of running the engine for one Pipeline Run.

| Field | Type | Required |
|-------|------|----------|
| run_id | ref Pipeline Run | yes |
| item_id | ref Checklist Item | yes |
| result | enum {PASS, FAIL} | yes |
| raw_output | string (bounded) | yes |
| evaluated_at | ISO-8601 UTC | yes |

**Invariant**: run cannot reach `released` unless every automatable item is PASS.

## Entity: VM Domain

| Field | Type | Required |
|-------|------|----------|
| name | `f44-hardened-<run_id>` | yes |
| vcpus | int (default 4) | yes |
| memory_mib | int (default 8192) | yes |
| disk_gib | int (default 60) | yes |
| volume_path | path under lab user home | yes |
| network_profile | `nat-user-session` (v1 only) | yes |
| bootc_reference | registry ref | yes |
| ssh_authorized_fingerprint | sha256 | yes |
| forward_compat | struct with reserved fields for `vlan-bridge`, `isolated` profiles | yes |

## Entity: Registry Release

| Field | Type | Required |
|-------|------|----------|
| registry_ref | `quay.io/<ns>/hardened-f44:<tag>` | yes |
| digest | sha256 of pushed image | yes |
| pushed_at | ISO-8601 UTC | yes |
| pull_secret_provisioned_at_vm | bool | yes |

## Relationships

```
Image Definition ── builds ──▶ Pipeline Run ── produces ──▶ Registry Release
                                  │
                                  ├─ evaluates ─▶ Hardening Gate Verdict (per item)
                                  └─ releases ──▶ VM Domain
```

## State constraints

- A VM Domain's `bootc_reference` MUST equal the `registry_ref` of its producing run.
- A Pipeline Run with any FAIL Hardening Gate Verdict must be `failed` and must not
  be referenced by any VM Domain.
- Registry Release `digest` must equal the run's `built_image_digest`.
