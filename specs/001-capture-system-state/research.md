# Research: Capture Current System State

**Feature**: `001-capture-system-state` | **Date**: 2026-09-23

Phase 0 resolves every unknown that would otherwise be `NEEDS CLARIFICATION` in the plan.
All decisions are driven by the constitution, the spec, the clarification answers, and
what is practical on a stock Fedora host accessed via SSH from a macOS/Linux workstation.

---

## D1 — How is the capture executed?

**Decision**: A single checked-in Bash script, `scripts/capture-state.sh`, drives the whole
run. It issues a fixed, allowlisted list of read-only commands over `ssh` (BatchMode,
ConnectTimeout set), streams remote stdout back, and renders the Main Report and Packages
Appendix locally. No remote temp files. No interactive prompting.

**Rationale**: Satisfies Principle I (the capture is itself auditable automation), Principle
III (a fixed allowlist is the smallest possible trust surface), and FR-002/FR-002a
(read-only, no sudo). BatchMode forces non-interactivity, matching the spec's assumption
that ssh-agent/`~/.ssh/config` silently authorizes `chris@donnager-linux`.

**Alternatives considered**:
- Interactive ad-hoc `ssh` sessions — rejected: not reproducible, contradicts Principle I.
- Ansible playbook — rejected for this feature: heavier than needed for a one-host read-only
  observation pass; retained as a likely direction for the *multi-host* follow-up platform.

---

## D2 — Output artifact layout

**Decision**:
- Main Report: `state/donnager-linux-YYYYMMDD.md`
- Packages Appendix: `state/donnager-linux-YYYYMMDD-packages.md`

Both under `state/` at the repo root; `state/` itself is excluded by `.gitignore`
before either file is written (FR-012a). The script refuses to run unless
`git check-ignore state/donnager-linux-YYYYMMDD.md` succeeds.

**Rationale**: SC-006 reviewability (short main report), FR-003 appendix split,
FR-012 / FR-012a no-commit guarantee with a structural guard.

**Alternatives considered**:
- Single self-contained file — rejected: contradicts Clarification Q3 (appendix split)
  and SC-006.
- Reports under `docs/` — rejected: user explicitly chose `state/` in Clarification Q2.

---

## D3 — Privilege policy and observation allowlist

**Decision**: Zero sudo, zero privilege escalation. Every remote command in the script is
tagged implicitly as `unprivileged`. Commands that commonly require root are attempted
*unprivileged* (e.g., `bootctl` may return partial data, `firewall-cmd --list-all` may
fail, `virsh -c qemu:///system list --all` is replaced by `virsh list --all` against the
default user session URI). When an unprivileged attempt fails, the report records
`not captured (no sudo)` for that observation, plus a one-line note of what would have
been observed.

**Rationale**: Clarification Q1 + Principle III. Coverage is traded for a defensible
privilege boundary; the tradeoff is explicit in the report.

**Alternatives considered**:
- Allow passwordless sudo for `firewall-cmd`/`virsh` — rejected: user explicitly declined.
- Skip privileged observations silently — rejected: SC-001 requires explicit absence
  markers, not silent omission.

---

## D4 — Command inventory (observational, unprivileged, read-only)

**Decision**: fixed allowlist, grouped per domain. Representative inventory (exact strings
in `scripts/capture-state.sh`; every invocation is echoed into the Provenance section):

- Host context: `hostname`, `hostnamectl`, `uname -a`, `cat /etc/os-release`,
  `cat /proc/cmdline`, `lscpu`, `lsblk -o …`, `findmnt -R / -o …`, `getenforce`,
  `bootctl 2>&1 || true`, `mokutil --sb-state 2>&1 || true`,
  `ls /sys/kernel/iommu_groups 2>/dev/null | head -n 20`, `nvidia-smi -L 2>&1 || true`,
  `nvidia-smi --query 2>&1 | head -n 40 || true`.
- Packages: `rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{VENDOR}\t%{DISTRIBUTION}\n' | sort`
  (appendix), `dnf -q repoquery --installed --qf '%{name}\t%{reponame}' 2>/dev/null | sort -u`
  (per-repo counts; falls back gracefully if unavailable).
- Network: `ip -brief address`, `ip -brief link`, `ip route`, `ip -6 route`,
  `resolvectl status 2>&1 || true`, `cat /etc/resolv.conf`,
  `ss -tulpn 2>&1 || true`, `nmcli -t general status 2>&1 || true`,
  `firewall-cmd --state 2>&1 || true` + `firewall-cmd --get-default-zone 2>&1 || true`
  (failures → `not captured (no sudo)`).
- Containers: `command -v podman docker`, `podman ps -a --format …` or
  `docker ps -a` (whichever exists; failures → absent marker), `podman images --format …`,
  `podman network ls`, `podman volume ls`, `podman system info 2>&1 | head -n 40`.
- Services: `systemctl list-unit-files --state=enabled --no-pager --no-legend`,
  `systemctl --failed --no-pager --no-legend`, `systemctl list-units --type=service
  --state=running --no-pager --no-legend`, and the same three with `systemctl --user`
  (using `XDG_RUNTIME_DIR` auto-detected; failure → `not captured (no sudo)` not required
  here but `not captured (user systemd unavailable)` is allowed under the same marker
  mechanism).
- VMs / libvirt: `command -v virsh`, `virsh list --all 2>&1 || true`,
  `virsh net-list --all 2>&1 || true`, `virsh pool-list --all 2>&1 || true`,
  each against the default user URI; failures → `not captured (no sudo)` (system URI
  deliberately not attempted per Q1).
- Repo cross-reference: local-only — script enumerates curated repo files
  (`installer.yaml`, `install-gcc-13.yaml`, `cuda-install.sh`, `scripts/granite-20.sh`,
  `bash_profile`, `bashrc`, `gpg-agent.conf`, `gpg.conf`, `ssh-config`,
  `nvidia-driver.md`, `hard-to-automate.md`, `thunderbird.md`, `bootc/Containerfile`)
  with one-line hints for the reviewer; does not auto-decide keep/remove.

**Alternatives considered**:
- `collectl`/`sosreport`-style broad gatherers — rejected: unbounded surface, often
  require root, contradict Principle III minimisation.
- Agent-based scraping via Python on remote — rejected: adds a runtime dependency on
  the target for a one-off capture.

---

## D5 — Sensitive-data posture

**Decision**: the report assumes it will contain hostname, IPs, MACs, local usernames.
Protection is structural, not redactional: `state/` is git-ignored (FR-012a) and the script
never invokes commands whose entire purpose is secret material — explicitly, no reads of
`~/.ssh/*` contents, `~/.gnupg/*`, `~/.aws/*`, `/etc/shadow`, keytabs, or `pass` stores.
Directory listings of these paths are also avoided.

**Rationale**: Clarification Q2 + Assumptions. Minimum surface, defensible by construction.

**Alternatives considered**:
- Pattern-based redaction (regex IP masking, etc.) — rejected: false-sense-of-security and
  unnecessary for an uncommitted local artifact.

---

## D6 — Repo-side cross-reference strategy

**Decision**: the script emits a "Repo artifacts" section with a table of curated
root-level files and a `Disposition (reviewer)` column pre-filled with `TODO`. The
reviewer (agent during implement, or human) fills in keep/remove/migrate per file based on
the captured live state. The script does NOT auto-mark anything as dead.

**Rationale**: SC-003 and FR-011 require the cross-reference to exist; automating the
*judgement* call would be unreliable — the value is the human/agent decision recorded
next to live evidence.

**Alternatives considered**:
- Fully automated classification (e.g., grep RPM list for script names) — rejected: high
  false-positive rate, produces noise instead of signal.

---

## D7 — Idempotency and rerun behaviour

**Decision**: same-day reruns overwrite the day's artifacts; new day → new date-stamped
files. The script never deletes older artifacts. Exit codes are conservative (see
`contracts/capture-cli.md`).

**Rationale**: enables debugging re-runs without losing prior baselines; complies with
FR-002 (no upstream mutation) and avoids surprise data loss.

**Alternatives considered**:
- Always create unique files with timestamps to the second — rejected: noise, duplicates
  clutter `state/`; date-stamped files strike the right balance for this repo.

---

## All NEEDS CLARIFICATION items: **none remain**.

Every decision above is recorded against a named decision ID (D1–D7) so that
`data-model.md`, `contracts/`, and `quickstart.md` can reference the rationale without
duplicating it.
