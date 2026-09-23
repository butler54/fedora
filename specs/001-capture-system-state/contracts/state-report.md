# Contract: State Report Structure

**Feature**: `001-capture-system-state` | **Date**: 2026-09-23

Contract for the two Markdown artifacts produced by `scripts/capture-state.sh`.
Consumers are human reviewers and downstream migration specs.

## Files

1. **Main Report** — `state/donnager-linux-YYYYMMDD.md`
2. **Packages Appendix** — `state/donnager-linux-YYYYMMDD-packages.md`

Both MUST be untracked by git (see FR-012, FR-012a). The capture driver refuses to
write them if they are not ignored.

## Main Report — required heading structure

Top-level headings appear in exactly this order. Subsection ordering inside a domain
is: **Observations**, **Findings**, (optional) **Notes**.

```
# State Snapshot — donnager-linux — YYYY-MM-DD

## Snapshot
## Host Context
## Packages
## Network
## Containers
## Services
## Virtual Machines
## Repo Artifacts
## Provenance
```

### `## Snapshot`

| Field | Required |
|-------|----------|
| Hostname | yes |
| FQDN | yes |
| Captured at (UTC) | yes |
| Operator | yes |
| Project git ref | yes |
| Feature ID (`001-capture-system-state`) | yes |

### Per-domain sections (`Host Context`, `Packages`, `Network`, `Containers`, `Services`, `Virtual Machines`)

Each domain MUST contain exactly these subsections, in this order:

#### `### Observations`

Markdown table:

| Observation | Value | Source |
|---|---|---|
| short label | value or summary | `command` |

If a section cannot be populated, in place of the table insert a single line with
one of the markers:

- `absent` — subsystem not present on host (e.g., no container runtime).
- `not captured (no sudo)` — requires privilege; never attempted per Clarification Q1.
- `not captured (user systemd unavailable)` — only valid in `### Services > User`.

#### `### Findings`

Either:

- A markdown table with columns `Item | Evidence | Suggested disposition | Note`, or
- The single literal line `none identified`.

No silent omissions (SC-003).

#### `### Notes` (optional)

Freeform commentary tying observations to findings.

### `## Packages` subsection constraints

- Observations table contains ONLY summary rows: `total installed`, per-repository
  counts, and any highlight rows (e.g., `kernel`, `akmods`, `nvidia-driver`).
- The full list is NOT inlined (SC-006). Link to the appendix:

  ```
  Full list: [donnager-linux-YYYYMMDD-packages.md](./donnager-linux-YYYYMMDD-packages.md)
  ```

### `## Repo Artifacts`

Markdown table (fixed column order):

| Path | Category | Disposition | Reviewer note |
|------|----------|-------------|---------------|

`Disposition` enum: `keep`, `remove`, `migrate`, `investigate`, `TODO`. Fresh reports
contain only `TODO`; the reviewer converts them during implementation review.

### `## Provenance`

Single markdown table (fixed column order):

| # | Side | Command | Exit | Sudo | Timestamp (UTC) |
|---|------|---------|------|------|------------------|

Every remote command issued by the driver MUST appear as exactly one row. `Sudo` is
always `no` per Clarification Q1.

## Packages Appendix — required structure

```
# Packages — donnager-linux — YYYY-MM-DD

## Snapshot
(same fields as Main Report)

## Packages (N total)

| Name | Version-Release | Vendor |
|------|------------------|--------|
| …    | …                | …       |
```

- Alphabetically sorted by `Name`.
- `N total` MUST equal `total installed` row in Main Report (SC-005 consistency).

## Marker literals (do not paraphrase)

These exact strings are the contract for absence:

- `absent`
- `not captured (no sudo)`
- `not captured (user systemd unavailable)`

Downstream scripts and reviewers may grep for them; paraphrasing breaks the contract.

## Size constraint

Body of Main Report (excluding Provenance table): target ≤ 400 lines
(SC-006: reviewable in one sitting). Hard ceiling 800 lines; exceeding it is a bug
to file against `scripts/capture-state.sh`.
