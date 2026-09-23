# Quickstart: Capture Current System State

**Feature**: `001-capture-system-state` | **Date**: 2026-09-23

Runnable validation scenarios proving the feature works end-to-end. Constitution
compliance (specifically FR-012a) is checked first.

## Prerequisites

- Working tree of this repository on a workstation with outbound SSH.
- Existing `~/.ssh/config` or ssh-agent allows non-interactive (`BatchMode`) SSH to
  `chris@donnager-linux`.
- `git`, `bash` ≥ 5, `ssh`, coreutils available locally.
- On the remote: standard Fedora userland; no sudo, no new packages are introduced.

## Q1 — `.gitignore` precondition (FR-012a)

```
# 1. Ensure state/ is ignored BEFORE running the capture
git check-ignore -v state/donnager-linux-$(date -u +%Y%m%d).md
# Expected: line referencing .gitignore and an exit code of 0.

# 2. Confirm nothing in state/ would be committed
git status --porcelain state/  # Expected: empty (untracked and ignored)
```

If `git check-ignore` exits non-zero, stop and update `.gitignore` first. Do NOT
run the capture.

## Q2 — Lint the driver

```
bash -n scripts/capture-state.sh && echo bash-syntax-ok
shellcheck scripts/capture-state.sh   # Expected: no errors (warnings triaged)
```

## Q3 — Dry run (no SSH, no writes)

```
scripts/capture-state.sh --dry-run
# Expected: prints the allowlisted command inventory grouped by domain, then exits 0.
# Verify: output shows "sudo" nowhere; commands are read-only.
```

## Q4 — Live capture (read-only)

```
scripts/capture-state.sh
# Expected exit code: 0
# Expected stdout: one progress line per domain, no sudo, no remote writes.
```

## Q5 — Validate artifacts (SC-001, SC-003, SC-004, SC-005, SC-006)

```
DATE=$(date -u +%Y%m%d)

# Exist
test -f "state/donnager-linux-${DATE}.md"
test -f "state/donnager-linux-${DATE}-packages.md"

# Not committed / not staged
git status --porcelain | grep state/   # Expected: no output
git log --oneline --all -- 'state/'    # Expected: empty

# Main report structure (matches contracts/state-report.md)
grep -E '^## (Snapshot|Host Context|Packages|Network|Containers|Services|Virtual Machines|Repo Artifacts|Provenance)$' \
  "state/donnager-linux-${DATE}.md" | wc -l    # Expected: 9

# Every domain has a Findings subsection
grep -c '^### Findings$' "state/donnager-linux-${DATE}.md"    # Expected: ≥ 6

# No silent omission: every Findings is either a table or the literal
grep -A2 '^### Findings$' "state/donnager-linux-${DATE}.md"

# Provenance table present and non-trivial
awk '/^## Provenance$/{flag=1; next} flag && /^\| [0-9]/' "state/donnager-linux-${DATE}.md" | wc -l   # Expected: ≥ 20

# Appendix count matches main report's "total installed"
grep -E '^## Packages \([0-9]+ total\)' "state/donnager-linux-${DATE}-packages.md"
grep -E 'total installed' "state/donnager-linux-${DATE}.md"

# Main report size under contract ceiling
wc -l "state/donnager-linux-${DATE}.md"   # Expected: ≤ 800 lines
```

## Q6 — Read-only proof (SC-002)

Manually review `state/donnager-linux-<date>.md` — Provenance section: every
command uses read-only flags (`list`, `show`, `cat`, `status`, `ps`, `-qa`,
etc.), and `Sudo` column is `no` for all rows. Optional spot check on target:

```
ssh chris@donnager-linux 'rpm -qa | wc -l'   # matches Main Report
ssh chris@donnager-linux 'systemctl list-units --type=service --state=running --no-pager --no-legend | wc -l'
```

Counts should match the capture within run-to-run jitter (≤ a few units / packages
if something naturally started or updated between runs).

## Manual review step (SC-003 closure)

Open `state/donnager-linux-<DATE>.md`:

- Each `### Findings` is either a populated table or the literal `none identified`.
- The `## Repo Artifacts` table contains rows for `installer.yaml`,
  `install-gcc-13.yaml`, `cuda-install.sh`, `scripts/granite-20.sh`,
  `nvidia-driver.md`, `hard-to-automate.md`, plus relevant dotfiles.
- Reviewer converts each `Disposition: TODO` to `keep/remove/migrate/investigate`.

This step is intentionally manual — automation decides what's suspicious, a human
(or an agent under review) decides what to do about it.
