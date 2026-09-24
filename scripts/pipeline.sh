#!/usr/bin/env bash
# scripts/pipeline.sh — hardened F44 VM pipeline (feature 002).
# Stages: preflight → build → scan → validate → push → vm
# Exit codes per contracts/pipeline-cli.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/pipeline-lib.sh
. "$SCRIPT_DIR/lib/pipeline-lib.sh"

EXIT_OK=0 EXIT_USAGE=1 EXIT_PREFLIGHT=2 EXIT_BUILD=3 EXIT_GATE=4 EXIT_PUSH=5 EXIT_VM=6 EXIT_COLLISION=7

usage() {
  cat <<'EOF'
Usage: scripts/pipeline.sh [options]
  --host HOST              ssh target (default: chris@donnager-linux)
  --registry-ref REF       push target (default: bootc/variables.env REGISTRY_REF_DEFAULT)
  --vm-name NAME           libvirt domain (default: f44-hardened-<run_id>)
  --vcpus N                default 4
  --memory-mib N           default 8192
  --disk-gib N             default 60
  --network-profile NAME   default nat-user-session
  --run-id ID              override run id
  --fixture DIR            build from a fixture build-context instead of bootc/
  --dry-run                print resolved plan; no side effects
  --help
Exit codes: 0 ok, 1 usage, 2 preflight, 3 build, 4 gate, 5 push, 6 vm, 7 collision.
EOF
  exit "${1:-1}"
}

HOST="chris@donnager-linux"
REGISTRY_REF=""
VM_NAME=""
VCPUS=4 MEMORY_MIB=8192 DISK_GIB=60
NETWORK_PROFILE="nat-user-session"
RUN_ID=""
DRY_RUN=0
FIXTURE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --registry-ref) REGISTRY_REF="${2:?}"; shift 2 ;;
    --vm-name) VM_NAME="${2:?}"; shift 2 ;;
    --vcpus) VCPUS="${2:?}"; shift 2 ;;
    --memory-mib) MEMORY_MIB="${2:?}"; shift 2 ;;
    --disk-gib) DISK_GIB="${2:?}"; shift 2 ;;
    --network-profile) NETWORK_PROFILE="${2:?}"; shift 2 ;;
    --run-id) RUN_ID="${2:?}"; shift 2 ;;
    --fixture) FIXTURE_DIR="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage 0 ;;
    *) warn "unknown arg: $1"; usage 1 ;;
  esac
done

cd "$REPO_ROOT"
# shellcheck disable=SC1091
. bootc/variables.env

CTX_DIR="${FIXTURE_DIR:-bootc}"
RUN_ID="${RUN_ID:-$(gen_run_id)}"
VM_NAME="${VM_NAME:-f44-hardened-${RUN_ID}}"
REGISTRY_REF="${REGISTRY_REF:-$REGISTRY_REF_DEFAULT}"
HOSTTAG="${HOST#*@}"; HOSTTAG="${HOSTTAG%%.*}"
RECORD="$(record_file "$HOSTTAG")"
REPO_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

DUR_preflight=0 DUR_build=0 DUR_scan=0 DUR_validate=0 DUR_push=0 DUR_vm=0
RESULT=failed
BUILT_REF="hardened-f44:${RUN_ID}"
BUILT_DIGEST=""
VM_ADDR=""
SMOKE_ARMED=0
RECORD_WROTE=0
RESULT_NOTES="none"

finish() {
  local code=$?
  if [ "$SMOKE_ARMED" -eq 1 ]; then smoke_vm_destroy "$HOST" "$VM_NAME" || true; fi
  if [ "$RECORD_WROTE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    write_record || true
  fi
  exit "$code"
}
trap finish EXIT

if [ "$DRY_RUN" -eq 1 ]; then
  cat <<EOF
pipeline dry-run
  host:            $HOST
  run_id:          $RUN_ID
  repo commit:     $REPO_COMMIT
  build context:   $CTX_DIR/
  registry ref:    $REGISTRY_REF
  vm name:         $VM_NAME  (${VCPUS}cpu/${MEMORY_MIB}MiB/${DISK_GIB}GiB)
  network profile: $NETWORK_PROFILE
  base:            ${BASE_IMAGE}@${BASE_DIGEST}
  builder:         ${BUILDER_IMAGE}@${BUILDER_DIGEST}
  stages:          preflight → build → scan → validate → push → vm
  record:          $RECORD
EOF
  RECORD_WROTE=1
  exit $EXIT_OK
fi

# ---------------------------------------------------------------- stage: preflight
stage_preflight() {
  stage_tic
  ssh_run "$HOST" true >/dev/null 2>&1 \
    || { RESULT_NOTES="ssh not BatchMode-capable to $HOST"; die "ssh not non-interactive" $EXIT_PREFLIGHT; }
  git check-ignore -q state/.keep || { RESULT_NOTES="state/ not git-ignored"; die "state/ not git-ignored" $EXIT_PREFLIGHT; }
  ssh_run "$HOST" "mkdir -p \$HOME/vms \$HOME/pipeline-work && test \$(df -BG --output=avail \$HOME/vms | tail -1 | tr -dc 0-9) -ge 40" \
    || { RESULT_NOTES="disk <40GiB in ~/vms"; die "insufficient disk in ~/vms on $HOST" $EXIT_PREFLIGHT; }
  command -v gomplate >/dev/null 2>&1 \
    || { RESULT_NOTES="gomplate missing on authoring host"; die "gomplate required locally (renders config.toml)" $EXIT_PREFLIGHT; }
  local actual
  actual="$(ssh_run "$HOST" "skopeo inspect 'docker://${BASE_IMAGE}' 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)[\"Digest\"])' || true")"
  if [ -n "$actual" ] && [ "$actual" != "$BASE_DIGEST" ]; then
    RESULT_NOTES="base digest drift pin=$BASE_DIGEST actual=$actual"
    die "digest pin mismatch (bump variables.env explicitly)" $EXIT_PREFLIGHT
  fi
  DUR_preflight=$(stage_toc)
}

# ---------------------------------------------------------------- lid + stage: build
lid_check() {
  # Duplicate declaration check: no package may be a member of a declared group.
  local cf="$CTX_DIR/Containerfile"
  local groups pkgs
  groups="$(grep -oE '@[a-z0-9-]+' "$cf" 2>/dev/null | sed 's/^@//' | sort -u || true)"
  [ -n "$groups" ] || return 0
  pkgs="$(awk '/^RUN dnf install/{flag=1} flag{print} /&&/{if(flag&&/clean/)flag=0}' "$cf" \
    | tr ' ' '\n' | grep -E '^[a-z0-9][a-z0-9+_.-]+$' | grep -vE '^(dnf|install|clean|all|rm|rf|var|cache|log|RUN|set|e|echo|if|fi|then|else|rpm|q|xorg.*|openssh.*|selinux.*|podman|true|false|[0-9]+)$' \
    | grep -v '^@' | sort -u || true)"
  [ -n "$pkgs" ] || { log "[lid] no bare packages declared — bundle-only (OK)"; return 0; }

  local groupdump=""
  local g
  for g in $groups; do
    groupdump+=$(ssh_run "$HOST" "dnf group info '$g' 2>/dev/null")
  done
  local dup=""
  local p
  for p in $pkgs; do
    if printf '%s' "$groupdump" | grep -qE "^[[:space:]]+${p}( |$|[[:space:]])"; then
      dup+="$p "
    fi
  done
  [ -z "$dup" ] || { RESULT_NOTES="lid violation: ${dup}"; die "lid duplicate declarations: ${dup}" $EXIT_BUILD; }
  log "[lid] OK (no package duplicates inside declared groups)"
}

stage_build() {
  stage_tic
  lid_check
  local remote_ctx="\$HOME/pipeline-work/ctx-${RUN_ID}"
  ssh_push_dir "$HOST" "$CTX_DIR/" "$remote_ctx/"
  ssh_run "$HOST" "cd $remote_ctx && podman build --rm -t '${BUILT_REF}' . >/tmp/build-${RUN_ID}.log 2>&1" \
    || { RESULT_NOTES="podman build failed (see $HOST:/tmp/build-${RUN_ID}.log)"; die "image build failed" $EXIT_BUILD; }
  BUILT_DIGEST="$(digest_of_image "$HOST" "$BUILT_REF")"
  [ -n "$BUILT_DIGEST" ] || { RESULT_NOTES="no digest for ${BUILT_REF}"; die "built digest missing" $EXIT_BUILD; }
  log "[build] ${BUILT_REF} digest=${BUILT_DIGEST}"
  # record group expansion evidence
  {
    printf '\n#### Bundle evidence (run %s)\n\n' "$RUN_ID"
    printf '```\n'
    ssh_run "$HOST" "for g in \$(grep -oE '@[a-z0-9-]+' $remote_ctx/Containerfile 2>/dev/null | sed 's/^@//' | sort -u); do dnf group info \"\$g\"; done" >>"$RECORD" 2>/dev/null || true
    printf '```\n'
  } >>"$RECORD"
  DUR_build=$(stage_toc)
}

# ---------------------------------------------------------------- stage: scan
stage_scan() {
  stage_tic
  ssh_push_dir "$HOST" "scripts/" "\$HOME/pipeline-work/scripts/"
  ssh_run "$HOST" "CTX_DIR_OVERRIDE='\$HOME/pipeline-work/ctx-${RUN_ID}' IMAGE_REF='${BUILT_REF}' bash \$HOME/pipeline-work/scripts/hardening-verify.sh --phase image" \
    || { RESULT_NOTES="image-phase hardening FAIL"; die "hardening gate (image phase) failed" $EXIT_GATE; }
  DUR_scan=$(stage_toc)
}

# ---------------------------------------------------------------- stage: validate
stage_validate() {
  stage_tic
  # Render bib config locally, push to host
  render_config
  ssh_push_dir "$HOST" "$CTX_DIR/" "\$HOME/pipeline-work/ctx-${RUN_ID}/"
  build_qcow2
  SMOKE_ARMED=1
  smoke_vm_start "$HOST" "$VM_NAME" "\$HOME/vms/${VM_NAME}.qcow2" 2 4096 >/dev/null
  local smoke_ip
  if ! smoke_ip="$(smoke_vm_addr "$HOST" "$VM_NAME")"; then
    RESULT_NOTES="smoke VM never acquired an address"
    die "smoke boot failed" $EXIT_GATE
  fi
  ssh_run "$HOST" "VM_IP='$smoke_ip' VM_USER=chris IMAGE_REF='${BUILT_REF}' bash \$HOME/pipeline-work/scripts/hardening-verify.sh --phase runtime" \
    || { RESULT_NOTES="runtime hardening FAIL"; die "hardening gate (runtime phase) failed" $EXIT_GATE; }
  smoke_vm_destroy "$HOST" "$VM_NAME"; SMOKE_ARMED=0
  DUR_validate=$(stage_toc)
}

render_config() {
  [ -n "${SSH_PUBKEY:-}" ] || die "SSH_PUBKEY env var required (contents of an authorized public key)" $EXIT_PREFLIGHT
  VM_HOSTNAME="$VM_NAME" gomplate -f "$CTX_DIR/config.toml.tmpl" -o "$CTX_DIR/config.toml"
  trap "rm -f $CTX_DIR/config.toml" RETURN
}

build_qcow2() {
  ssh_run "$HOST" "set -e
    test -f \$HOME/vms/${VM_NAME}.qcow2 && { echo 'qcow exists'; exit 7; }
    podman run --rm --privileged \
      -v \$HOME/pipeline-work/ctx-${RUN_ID}:/cfg \
      -v \$HOME/vms:/out \
      '${BUILDER_IMAGE}@${BUILDER_DIGEST}' \
      build '${BUILT_REF}' --config /cfg/config.toml --type qcow2 --output /out \
      >/tmp/bib-${RUN_ID}.log 2>&1" \
    || { rc=$?; [ "$rc" -eq 7 ] && { RESULT_NOTES="qcow2 collision"; die "qcow2 exists" $EXIT_COLLISION; }; \
         RESULT_NOTES="bib failed (log: /tmp/bib-${RUN_ID}.log)"; die "bib qcow2 failed" $EXIT_GATE; }
  ssh_run "$HOST" "qemu-img resize \$HOME/vms/${VM_NAME}.qcow2 ${DISK_GIB}G >/dev/null 2>&1 || true"
}

# ---------------------------------------------------------------- stage: push
stage_push() {
  stage_tic
  require_env QUAY_USER $EXIT_PUSH
  require_env QUAY_TOKEN $EXIT_PUSH
  ssh_run "$HOST" "podman tag '${BUILT_REF}' '${REGISTRY_REF}'"
  printf '%s' "$QUAY_TOKEN" | ssh -o BatchMode=yes "$HOST" "podman login --username '${QUAY_USER}' --password-stdin >/dev/null" \
    || { RESULT_NOTES="registry login failed"; die "podman login failed" $EXIT_PUSH; }
  ssh_run "$HOST" "podman push --quiet '${REGISTRY_REF}'" \
    || { RESULT_NOTES="registry push failed"; die "push failed" $EXIT_PUSH; }
  local pushed
  pushed="$(ssh_run "$HOST" "skopeo inspect 'docker://${REGISTRY_REF}' 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)[\"Digest\"])' || true")"
  [ -n "$pushed" ] && BUILT_DIGEST="$pushed"
  DUR_push=$(stage_toc)
}

# ---------------------------------------------------------------- stage: vm
stage_vm() {
  stage_tic
  if ssh_run "$HOST" "virsh -c qemu:///session dominfo '${VM_NAME}'" >/dev/null 2>&1; then
    RESULT_NOTES="domain collision: ${VM_NAME}"
    die "domain exists" $EXIT_COLLISION
  fi
  ssh_run "$HOST" "set -e
    virt-install --connect qemu:///session --name '${VM_NAME}' \
      --vcpus '${VCPUS}' --memory '${MEMORY_MIB}' \
      --disk path=\$HOME/vms/${VM_NAME}.qcow2,format=qcow2,bus=virtio \
      --import --os-variant fedora-unknown --noautoconsole \
      --network network=default,model=virtio >/dev/null" \
    || { RESULT_NOTES="virt-install failed"; die "vm creation failed" $EXIT_VM; }
  local i addr
  for i in $(seq 1 24); do
    addr="$(ssh_run "$HOST" "virsh -c qemu:///session domifaddr '${VM_NAME}' --source arp 2>/dev/null | awk '/ipv4/{print \$4}' | cut -d/ -f1 | head -1" || true)"
    [ -n "$addr" ] && { VM_ADDR="$addr"; break; }
    sleep 5
  done
  RESULT=released
  RESULT_NOTES="vm started${VM_ADDR:+ at ${VM_ADDR}}"
  DUR_vm=$(stage_toc)
}

# ---------------------------------------------------------------- record
write_record() {
  RECORD_WROTE=1
  mkdir -p state
  {
    printf '\n---\n\n## Run %s\n\n' "$RUN_ID"
    printf -- '- Repo commit: %s\n' "$REPO_COMMIT"
    printf -- '- Stage durations: preflight=%ss build=%ss scan=%ss validate=%ss push=%ss vm=%ss\n' \
      "$DUR_preflight" "$DUR_build" "$DUR_scan" "$DUR_validate" "$DUR_push" "$DUR_vm"
    printf -- '- Result: %s\n' "$RESULT"
    printf '\n### Images\n\n| Role | Reference | Digest |\n|------|-----------|--------|\n'
    printf '| base | %s | %s |\n' "$BASE_IMAGE" "$BASE_DIGEST"
    printf '| builder | %s | %s |\n' "$BUILDER_IMAGE" "$BUILDER_DIGEST"
    printf '| built | %s | %s |\n' "$REGISTRY_REF" "${BUILT_DIGEST:-unknown}"
    printf '\n### VM\n\n- Domain: %s\n- vcpus/memory/disk: %s/%sMiB/%sGiB\n- network profile: %s\n- bootc reference: %s\n- reachable address: %s\n' \
      "${VM_NAME:-null}" "$VCPUS" "$MEMORY_MIB" "$DISK_GIB" "$NETWORK_PROFILE" "$REGISTRY_REF" "${VM_ADDR:-null}"
    printf '\n### Notes\n\n%s\n' "$RESULT_NOTES"
  } >>"$RECORD"
}

main() {
  stage_preflight
  stage_build
  stage_scan
  stage_validate
  stage_push
  stage_vm
  log "[pipeline] $RESULT (${RUN_ID})"
}

main
