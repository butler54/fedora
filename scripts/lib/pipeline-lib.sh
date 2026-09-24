#!/usr/bin/env bash
# scripts/lib/pipeline-lib.sh — shared helpers for the hardened VM pipeline.
# Sourced by scripts/pipeline.sh and scripts/hardening-verify.sh.
# Conventions mirror contracts/pipeline-cli.md and contracts/execution-record.md.

set -euo pipefail

# --- logging -----------------------------------------------------------------
log()  { printf '%s\n' "$*" >&1; }
warn() { printf '[warn] %s\n' "$*" >&2; }
die()  { printf '[error] %s\n' "$*" >&2; exit "${2:-1}"; }

# --- timing ------------------------------------------------------------------
STAGE_T0=0
stage_tic() { STAGE_T0=$(date +%s); }
stage_toc() { echo $(( $(date +%s) - STAGE_T0 )); }
now_utc() { date -u +%FT%TZ; }
run_id_today() { date -u +%Y%m%d; }
gen_run_id() { date -u +%Y%m%d-%H%M%S; }

# --- ssh ---------------------------------------------------------------------
# All remote access uses BatchMode; connection reuse via caller's ControlPath.
: "${SSH_OPTS_ARR:=}"
SSH_OPTS_DEFAULT=(
  -o BatchMode=yes
  -o ConnectTimeout=6
  -o ControlMaster=auto
  -o "ControlPath=$HOME/.ssh/ctl-pipeline-%C"
  -o ControlPersist=120
)

ssh_run() {
  local host="$1" cmd="$2"
  # shellcheck disable=SC2068
  ssh ${SSH_OPTS_ARR[@]:-${SSH_OPTS_DEFAULT[@]}} "$host" "$cmd"
}

# rsync a local dir to the host's home tmp area (no sudo needed)
ssh_push_dir() {
  local host="$1" src="$2" dst="$3"
  rsync -az --delete -e "ssh ${SSH_OPTS_ARR[*]:-${SSH_OPTS_DEFAULT[*]}}" "$src/" "$host:$dst/"
}

ssh_pull_file() {
  local host="$1" remote="$2" localf="$3"
  # shellcheck disable=SC2068
  scp ${SSH_OPTS_ARR[@]:-${SSH_OPTS_DEFAULT[@]}} -q "$host:$remote" "$localf"
}

# --- digests -----------------------------------------------------------------
digest_of_image() {
  # $1 host, $2 ref → prints sha256 digest; empty on failure
  ssh_run "$1" "podman inspect --format '{{.Digest}}' '$2' 2>/dev/null || true"
}

remote_pull_if_missing() {
  local host="$1" ref="$2"
  ssh_run "$host" "podman image exists '$ref' || podman pull --quiet '$ref'" >/dev/null
}

# --- execution record --------------------------------------------------------
# record_file HOSTTAG [DATE] → path of today's record (state/)
record_file() {
  local hosttag="$1" date="${2:-$(run_id_today)}"
  echo "state/${hosttag}-${date}.pipeline-run.md"
}

record_kv() {
  # record_kv FILE key value
  printf -- '- %s: %s\n' "$2" "$3" >>"$1"
}

record_append() {
  # record_append FILE text-block
  printf '%s\n' "$2" >>"$1"
}

record_section() {
  printf '\n### %s\n\n' "$2" >>"$1"
}

record_table_row() {
  # record_table_row FILE "col1" "col2" "col3"
  printf '| %s | %s | %s |\n' "$2" "$3" "$4" >>"$1"
}

# --- smoke VM (user-session libvirt, transient) -------------------------------
SMOKE_SUFFIX="-smoke"

smoke_vm_name() { printf '%s%s\n' "$1" "$SMOKE_SUFFIX"; }

smoke_vm_start() {
  # smoke_vm_start HOST BASE_VM_NAME IMAGE_QCOW2_PATH_RAM [VCPUS] [MEM_MIB]
  local host="$1" name; name="$(smoke_vm_name "$2")"
  local qcow="$3" vcpus="${4:-2}" mem="${5:-4096}"
  ssh_run "$host" "set -e
    virsh -c qemu:///session dominfo '$name' >/dev/null 2>&1 && { echo 'smoke vm collision' >&2; exit 42; }
    cp '$qcow' '${qcow%.qcow2}${SMOKE_SUFFIX}.qcow2'
    virt-install --connect qemu:///session --name '$name' \
      --vcpus '$vcpus' --memory '$mem' \
      --disk 'path=${qcow%.qcow2}${SMOKE_SUFFIX}.qcow2,format=qcow2,bus=virtio' \
      --os-variant fedora-unknown --import --noautoconsole --network network=default,model=virtio \
      >/dev/null
    echo started"
}

smoke_vm_addr() {
  local host="$1" name; name="$(smoke_vm_name "$2")"
  for _ in $(seq 1 36); do   # ~3 min
    local addr
    addr="$(ssh_run "$host" "virsh -c qemu:///session domifaddr '$name' --source arp 2>/dev/null | awk '/ipv4/{print \$4}' | cut -d/ -f1 | head -1" || true)"
    [ -n "$addr" ] && { printf '%s' "$addr"; return 0; }
    sleep 5
  done
  return 1
}

smoke_vm_destroy() {
  local host="$1" name; name="$(smoke_vm_name "$2")"
  ssh_run "$host" "
    virsh -c qemu:///session destroy '$name' >/dev/null 2>&1 || true
    virsh -c qemu:///session undefine '$name' >/dev/null 2>&1 || true
    rm -f ~/vms/*${SMOKE_SUFFIX}.qcow2
  " || true
}

# --- misc --------------------------------------------------------------------
require_env() {
  local var="$1"
  [ -n "${!var:-}" ] || die "environment variable $var is required" "${2:-1}"
}

file_age_days() { echo $(( ( $(date +%s) - $(stat -f %m "$1") ) / 86400 )); }
