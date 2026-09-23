# Contract: `scripts/capture-state.sh` (Capture CLI)

**Feature**: `001-capture-system-state` | **Date**: 2026-09-23

## Purpose

Drive the read-only, unprivileged capture of `chris@donnager-linux` and emit the Main
Report and Packages Appendix under `state/`. The script is the only supported entry
point; ad-hoc SSH capture is out of contract.

## Usage

```
scripts/capture-state.sh [--host HOST] [--date YYYYMMDD] [--out-dir DIR] [--dry-run] [--help]
```

### Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--host HOST` | `chris@donnager-linux` | SSH target (user@host). Must resolve via `~/.ssh/config` or agent without prompting (BatchMode). |
| `--date YYYYMMDD` | today (UTC) | Override date stem used in artifact filenames. |
| `--out-dir DIR` | `state/` at repo root | Output directory. Must be git-ignored before run. |
| `--dry-run` | off | Print the allowlisted command inventory and exit; no SSH, no writes. |
| `--help` | — | Print usage. |

### Environment

| Variable | Effect |
|----------|--------|
| `SSH_OPTS` | Extra options appended to every `ssh` invocation (default: `-o BatchMode=yes -o ConnectTimeout=5`). |

## Preconditions (exit non-zero if any fails)

1. Repo root has a `.gitignore`; `git check-ignore <out-dir>/donnager-linux-<date>.md`
   (or equivalent) returns success — FR-012a.
2. `ssh -o BatchMode=yes <host> 'true'` succeeds and remote hostname matches
   `donnager-linux*`.
3. No existing non-writable artifact at the intended paths.

## Invariants

- **No sudo, no privilege escalation** on the remote host (Clarification Q1).
- **No writes on remote filesystem** — all data streamed back via stdout.
- **Fixed command allowlist** — every remote invocation appears verbatim in the script's
  `COMMANDS` array and hence in the Provenance section.
- Date-stamped overwrite policy: same-day reruns replace same-day artifacts; older
  artifacts are never deleted.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Capture completed; artifacts written; all required domains populated or explicitly marked. |
| `1` | Usage error (bad flag, bad date format, missing out-dir). |
| `2` | Precondition failed (git-ignore, ssh, hostname). |
| `3` | Remote invocation failed hard enough that ≥1 required domain cannot be produced. |

Domain-level `not captured (no sudo)` and `absent` markers do NOT cause a non-zero
exit (per FR-002a); they are captured in the report.

## Output artifacts (FR-012: never committed)

- `<out-dir>/donnager-linux-<date>.md` — Main Report (see `contracts/state-report.md`).
- `<out-dir>/donnager-linux-<date>-packages.md` — Packages Appendix (see `contracts/state-report.md`).
- `<out-dir>/donnager-linux-<date>.provenance.md` — raw command/outcome log (optional;
  emitted whenever the driver can; treated as part of the Main Report's provenance
  if embedded directly).

## Stdout / stderr

- `stdout`: high-level progress lines per domain (e.g., `[packages] 2147 installed
  packages (appendix)`).
- `stderr`: failures, precondition diagnostics, and `not captured` notices that
  terminate a domain.

## Non-goals

- No config templating, no mutation of the target host, no multi-host support.
- No post-processing of Findings — human/agent reviewer fills dispositions afterwards.
