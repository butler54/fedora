# Data Model: Capture Current System State

**Feature**: `001-capture-system-state` | **Date**: 2026-09-23

These entities describe the artifacts this feature produces and consumes. They are not
code classes; they are the structural contracts for what ends up in `state/`.

## Entity: State Snapshot

Top-level handle binding a capture run to a host at a moment in time.

| Field | Type | Required | Source |
|-------|------|----------|--------|
| hostname | string | yes | `hostname` on target |
| host_fqdn | string | yes | `hostname -f` falling back to `hostnamectl --static` |
| captured_at_utc | ISO-8601 UTC string | yes | driver `date -u +%FT%TZ` |
| operator | string | yes | local `$USER` |
| project_git_ref | string (short SHA) | yes | `git rev-parse --short HEAD` at driver start |
| feature_id | string | yes | constant `001-capture-system-state` |
| domains | list of Domain Section | yes | produced by driver |
| provenance | list of Provenance Entry | yes | recorded as commands execute |

**Validation rules**
- Exactly one snapshot per (hostname, capture date).
- `captured_at_utc` occurs before any Domain Section timestamp and after driver start.

## Entity: Main Report

Human-reviewable markdown document derived from a State Snapshot.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| path | `state/donnager-linux-YYYYMMDD.md` | yes | FR-012a precondition: parent dir git-ignored |
| snapshot | State Snapshot | yes | header block |
| domains | list of Domain Section (6) | yes | fixed order: context, packages, network, containers, services, vms |
| repo_artifacts | Repo Artifact (list) | yes | curated root-level repo files |
| appendix_links | list of file refs | yes | at least the Packages Appendix |
| provenance | list of Provenance Entry | yes | single table at document foot |

**Validation rules**
- First-level headings exactly match `contracts/state-report.md`.
- Length target: readable in < 10 minutes (SC-006). Full listings belong in Appendix.

## Entity: Appendix Report

Companion markdown artifact holding exhaustive listings for domains whose volume would
break SC-006. The Packages Appendix is mandatory; other appendices are optional.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| path | `state/donnager-linux-YYYYMMDD-packages.md` | yes | same date stem as Main Report |
| snapshot_ref | State Snapshot | yes | header mirrors Main Report header |
| items | list of strings | yes | one installed package per line, `name\tversion-release\tvendor` |

**Validation rules**
- Back-linked from Main Report under `## Packages`.
- Same no-commit handling as Main Report.

## Entity: Domain Section

One of the six fixed domains. Contains observations and a findings subsection.

| Field | Type | Required |
|-------|------|----------|
| id | enum {`host-context`,`packages`,`network`,`containers`,`services`,`vms`} | yes |
| title | string | yes |
| observations | list of Observation | yes |
| findings | list of Finding | yes |
| absence_marker | enum {`none`,`absent`,`not-captured-no-sudo`、`user-systemd-unavailable`} | yes |

**Validation rules**
- Each Domain Section is either populated with observations or has a non-`none`
  `absence_marker`. Never silently empty.

## Entity: Observation

One atomic piece of evidence recorded from a single remote (or local) read.

| Field | Type | Required |
|-------|------|----------|
| source_command | string (allowlisted) | yes |
| captured_value | string (verbatim or summarized) | yes |
| summary | string | yes |
| exit_code | int | yes |
| sudo_used | bool | yes (always `false` per Q1) |

**Validation rules**
- `source_command` must appear in the script's allowlist.
- A non-zero `exit_code` is only legal if the Observation is linked to an
  absence marker (`not-captured-no-sudo`) on the parent Domain Section.

## Entity: Finding

A "dead / suspect" item identified in a Domain Section.

| Field | Type | Required |
|-------|------|----------|
| domain_id | matches Domain Section id | yes |
| identifier | string (package/unit/container/vm/file name) | yes |
| evidence | short verbatim quote from Observation | yes |
| disposition_suggested | enum {`keep`,`remove`,`migrate`,`investigate`} | yes |
| note | string | no |

**Validation rules**
- If no Finding exists for a Domain Section, the section MUST instead contain an
  explicit `none identified` line (SC-003).

## Entity: Repo Artifact

Cross-reference row for files in this repository evaluated against live state.

| Field | Type | Required |
|-------|------|----------|
| path | repo-relative path | yes |
| category | enum {`script`,`ansible`,`dotfile`,`doc`,`image-def`} | yes |
| disposition | enum {`keep`,`remove`,`migrate`,`investigate`,`TODO`} | yes |
| reviewer_note | string | no |

**Validation rules**
- `TODO` is only legal in the freshly generated report; before SC-003 closure each
  row must move to a terminal disposition.

## Entity: Provenance Entry

Audit record of one command invocation.

| Field | Type | Required |
|-------|------|----------|
| command | string | yes |
| side | enum {`local`,`remote`} | yes |
| sudo | bool | yes (always `false`) |
| exit_code | int | yes |
| timestamp_utc | ISO-8601 UTC | yes |
| linked_observation_id | string or null | no |

**Validation rules**
- Replaying all rows with `exit_code == 0` reproduces every Observation in the
  Main Report (SC-005).

---

## Relationships

```
State Snapshot ── 1:1 ── Main Report
State Snapshot ── 1:N ── Appendix Report
Main Report   ── 1:6 ── Domain Section
Domain Section── 1:N ── Observation
Domain Section── 1:N ── Finding
Observation  ── 1:1 ── Provenance Entry
Main Report   ── 1:N ── Repo Artifact
```

## Lifecycle

```
(script start)
  → State Snapshot created (preconditions verified: state/ git-ignored, ssh ok, remote hostname matches)
  → Domain Sections filled sequentially
  → Findings summarized per section (or `none identified`)
  → Repo Artifacts table emitted (`TODO`)
  → Main Report + Appendix written
  → driver exits 0 on clean completion, non-zero on any script-level error
  → reviewer converts Repo Artifact `TODO`s to terminal dispositions (out of scope for this script)
```
