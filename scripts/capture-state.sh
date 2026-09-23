#!/usr/bin/env bash
# scripts/capture-state.sh
#
# Capture a read-only, unprivileged snapshot of a remote host into Markdown
# artifacts under state/ (git-ignored). Implements spec 001-capture-system-state.
#
# Guarantees (enforced, not aspirational):
#   - No sudo / no privilege escalation on the target
#   - No writes on the target filesystem (streamed over SSH stdout only)
#   - Fixed, allowlisted command inventory per domain
#   - Refuses to run unless state/ is git-ignored (FR-012a)
#
# Usage:
#   scripts/capture-state.sh [--host USER@HOST] [--date YYYYMMDD]
#                            [--out-dir DIR] [--dry-run] [--help]
#
# Exit codes:
#   0 success; 1 usage; 2 precondition; 3 remote/domain failure
#
# Examples:
#   scripts/capture-state.sh --dry-run
#   scripts/capture-state.sh
#   scripts/capture-state.sh --host chris@donnager-linux --date 20260923

set -euo pipefail

FEATURE_ID="001-capture-system-state"

EXIT_OK=0
EXIT_USAGE=1
EXIT_PRECONDITION=2
EXIT_DOMAIN_FAILURE=3

log()  { printf '%s\n' "$*" >&1; }
warn() { printf '[warn] %s\n' "$*" >&2; }
die()  { printf '[error] %s\n' "$*" >&2; exit "${2:-1}"; }

usage() {
  sed -n '2,30p' "$0" | sed -e 's/^# \{0,1\}//'
  exit "${1:-$EXIT_OK}"
}

HOST="chris@donnager-linux"
DATE_UTC="$(date -u +%Y%m%d)"
OUT_DIR=""
DRY_RUN=0
REPO_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host)    HOST="${2:?--host requires a value}"; shift 2 ;;
    --date)    DATE_UTC="${2:?--date requires YYYYMMDD}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:?--out-dir requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage $EXIT_OK ;;
    *) warn "unknown argument: $1"; usage $EXIT_USAGE ;;
  esac
done

case "$DATE_UTC" in
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
  *) die "invalid --date (expected YYYYMMDD): $DATE_UTC" "$EXIT_USAGE" ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "must run inside git repo" "$EXIT_PRECONDITION"
cd "$REPO_ROOT"

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$REPO_ROOT/state"
fi
mkdir -p "$OUT_DIR"

HOST_SHORT="${HOST##*@}"
HOST_TAG="${HOST_SHORT%%.*}"
CAPTURED_AT="$(date -u +%FT%TZ)"
OPERATOR="${USER:-unknown}"
GIT_REF="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
MAIN_REPORT="$OUT_DIR/${HOST_TAG}-${DATE_UTC}.md"
APPENDIX_PKG="$OUT_DIR/${HOST_TAG}-${DATE_UTC}-packages.md"
APPENDIX_SVC="$OUT_DIR/${HOST_TAG}-${DATE_UTC}-services.md"

# --- SSH plumbing -----------------------------------------------------------

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o ControlMaster=auto
  -o ControlPath="/tmp/capture-ssh-ctl-%C"
  -o ControlPersist=60
)

# Provenance log: file-based so entries survive command-substitution subshells.
PROV_FILE="$(mktemp /tmp/capture-prov.XXXXXX)"

prov_append() {
  local cmd="$1" code="$2" ts="$3"
  local seq
  seq=$(wc -l <"$PROV_FILE" | tr -d ' ')
  seq=$((seq + 1))
  printf '| %s | remote | `%s` | %s | no | %s |\n' \
    "$seq" "${cmd//|/\\|}" "$code" "$ts" >>"$PROV_FILE"
}

# run_remote CMD — runs CMD over ssh; prints stdout; returns exit code.
run_remote() {
  local cmd="$1" ts out code
  ts="$(date -u +%FT%TZ)"
  set +e
  out="$(ssh "${SSH_OPTS[@]}" "$HOST" "$cmd" 2>&1)"
  code=$?
  set -e
  prov_append "$cmd" "$code" "$ts"
  if [ "$code" -ne 0 ]; then
    return "$code"
  fi
  printf '%s' "$out"
  return 0
}

# join_lines — join multi-line stdout with ' ; ' separators (no trailing sep).
join_lines() {
  awk 'NF{a[NR]=$0} END{for(i=1;i<=NR;i++) printf "%s%s", a[i], (i<NR?" ; ":"")}'
}

# cap CMD — run remote, join multi-line output with ' ; '; never fails.
cap() {
  local out
  out="$(run_remote "$1" || true)"
  printf '%s\n' "$out" | join_lines
}

# cap_marker CMD MARKER — like cap, but substitutes MARKER if the command fails.
cap_marker() {
  local out
  if out="$(run_remote "$1")"; then
    printf '%s\n' "$out" | join_lines
  else
    printf '%s' "$2"
  fi
}

# --- Preconditions (T004) ---------------------------------------------------

check_preconditions() {
  if ! git check-ignore -q "$MAIN_REPORT"; then
    die "precondition failed: $MAIN_REPORT not git-ignored (FR-012a). Update .gitignore first." "$EXIT_PRECONDITION"
  fi

  if ! ssh "${SSH_OPTS[@]}" "$HOST" 'true' >/dev/null 2>&1; then
    die "precondition failed: ssh to $HOST not non-interactive (BatchMode). Check ssh-agent/config." "$EXIT_PRECONDITION"
  fi
  prov_append "true" 0 "$(date -u +%FT%TZ)"

  local remote_host
  remote_host="$(ssh "${SSH_OPTS[@]}" "$HOST" 'hostname' 2>/dev/null || true)"
  prov_append "hostname" 0 "$(date -u +%FT%TZ)"
  case "$remote_host" in
    donnager-linux*) : ;;
    *) die "precondition failed: remote hostname '$remote_host' does not match donnager-linux*" "$EXIT_PRECONDITION" ;;
  esac
}

# --- Domain command inventories (dry-run) ------------------------------------

dry_run() {
  cat <<'EOF'
=== Host Context ===
hostname
hostname -f
cat /etc/os-release (PRETTY_NAME, VERSION_ID)
uname -r
cat /proc/cmdline
lscpu (model, cpu count, virtualization)
lsblk -d -o NAME,TYPE,SIZE,MODEL
findmnt -no SOURCE,FSTYPE,OPTIONS /
getenforce
mokutil --sb-state
bootctl
ls /sys/kernel/iommu_groups | wc -l
test -c /dev/kvm
nvidia-smi -L
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

=== Packages (full → appendix) ===
rpm -qa --qf '%{NAME}|%{VERSION}-%{RELEASE}|%{VENDOR}\n' | sort

=== Packages (summary) ===
rpm -qa | wc -l
rpm -qa --qf '%{VENDOR}\n' | sort | uniq -c | sort -rn | head -n 8
rpm -q kernel akmods kmod-nvidia

=== Network ===
ip -brief address
ip -brief link
ip route
ip -6 route
cat /etc/resolv.conf (nameserver/search)
ss -tuln
ss -tulpn
nmcli general status, nmcli device status
firewall-cmd --state
firewall-cmd --get-default-zone

=== Containers ===
command -v podman docker
podman --version
podman ps -a / ps -a --filter status=exited
podman images / images -f dangling=true
podman network ls
podman volume ls
docker ps -a (if docker present)

=== Services (system + user) ===
systemctl list-unit-files --type=service --state=enabled
systemctl --failed
systemctl list-units --type=service --state=running
(same three via systemctl --user)

=== VMs ===
command -v virsh
virsh list --all
virsh list --all --inactive --name
virsh net-list --all
virsh pool-list --all
EOF
  exit $EXIT_OK
}

# --- Domain collectors -------------------------------------------------------

HOST_FILE="" NET_FILE="" PKG_FILE="" CTR_FILE="" SVC_FILE="" VM_FILE="" REPO_FILE=""

mktemp_domain() { mktemp /tmp/capture-domain.XXXXXX; }

obs_header() {
  printf '| Observation | Value | Source |\n'
  printf '|---|---|---|\n'
}

obs_row() {
  local label="$1" value="$2" source="$3"
  value="${value//|/\\|}"
  printf '| %s | %s | `%s` |\n' "$label" "$value" "$source"
}

findings_header() {
  printf '| Item | Evidence | Suggested disposition | Note |\n'
  printf '|------|----------|------------------------|------|\n'
}

findings_row() {
  local item="$1" ev="$2" disp="${3:-investigate}" note="${4:-}"
  item="${item//|/\\|}"; ev="${ev//|/\\|}"; note="${note//|/\\|}"
  printf '| %s | %s | %s | %s |\n' "$item" "$ev" "$disp" "$note"
}

section() { printf '## %s\n\n' "$1"; }
sub()     { printf '### %s\n\n' "$1"; }

collect_host_context() {
  HOST_FILE="$(mktemp_domain)"
  local o="$HOST_FILE"
  { section "Host Context"; sub "Observations"; obs_header; } >>"$o"

  obs_row "hostname"              "$(cap 'hostname')"                          "hostname"                                >>"$o"
  obs_row "fqdn"                  "$(cap 'hostname -f')"                       "hostname -f"                             >>"$o"
  obs_row "os-release"            "$(cap "grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release")" "cat /etc/os-release" >>"$o"
  obs_row "kernel"                "$(cap 'uname -r')"                          "uname -r"                                >>"$o"
  obs_row "cmdline"               "$(cap 'cat /proc/cmdline')"                 "cat /proc/cmdline"                       >>"$o"
  obs_row "cpu"                   "$(cap "lscpu | grep -E '^(Model name|CPU\(s\):)' | head -n 4")" "lscpu" >>"$o"
  obs_row "virtualization"        "$(cap "lscpu | grep -iE 'virtualization' || echo none")" "lscpu"                   >>"$o"
  obs_row "disks"                 "$(cap 'lsblk -d -o NAME,TYPE,SIZE,MODEL')"  "lsblk"                                   >>"$o"
  obs_row "root mount"            "$(cap 'findmnt -no SOURCE,FSTYPE,OPTIONS /')" "findmnt /"                             >>"$o"
  obs_row "selinux"               "$(cap 'getenforce')"                        "getenforce"                              >>"$o"
  obs_row "secure boot"           "$(cap 'mokutil --sb-state')"                "mokutil --sb-state"                      >>"$o"
  obs_row "firmware"              "$(cap "bootctl 2>&1 | grep -E 'Firmware|Secure Boot' | head -n 4 || echo unavailable")" "bootctl" >>"$o"
  obs_row "iommu groups"          "$(cap 'ls /sys/kernel/iommu_groups 2>/dev/null | wc -l')" "ls iommu_groups | wc -l"   >>"$o"
  obs_row "/dev/kvm"              "$(cap 'test -c /dev/kvm && echo present || echo absent')" "test -c /dev/kvm"          >>"$o"
  obs_row "gpu list"              "$(cap 'nvidia-smi -L')"                     "nvidia-smi -L"                           >>"$o"
  obs_row "gpu driver"            "$(cap 'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader')" "nvidia-smi --query-gpu" >>"$o"

  printf '\n' >>"$o"
  sub "Findings" >>"$o"
  {
    findings_header
    local any=0 selinux iommu
    selinux="$(cap 'getenforce')"
    iommu="$(cap 'ls /sys/kernel/iommu_groups 2>/dev/null | wc -l')"
    if [ "$selinux" != "Enforcing" ] && [ "$selinux" != "Enforcing ; " ]; then
      findings_row "selinux: ${selinux}" "expected Enforcing" "investigate" "constitution P.III requires hardened baseline"
      any=1
    fi
    if [ "${iommu%% ;*}" = "0" ] || [ "$iommu" = "0" ]; then
      findings_row "iommu-vgroups=0" "no /sys/kernel/iommu_groups entries" "investigate" "blocker for GPU passthrough / VFIO lab scenarios"
      any=1
    fi
    if [ "$any" -eq 0 ]; then printf 'none identified\n'; fi
  } >>"$o"
  log "[host-context] done"
}

collect_packages() {
  PKG_FILE="$(mktemp_domain)"
  local o="$PKG_FILE"

  {
    printf '# Packages — %s — %s\n\n' "$HOST_TAG" "$(date -u +%F)"
    printf '## Snapshot\n\n'
    printf -- '- Hostname: `%s`\n'          "$HOST_TAG"
    printf -- '- FQDN: `%s`\n'              "$(cap 'hostname -f')"
    printf -- '- Captured at (UTC): `%s`\n' "$CAPTURED_AT"
    printf -- '- Operator: `%s`\n'          "$OPERATOR"
    printf -- '- Project git ref: `%s`\n'   "$GIT_REF"
    printf -- '- Feature ID: `%s`\n\n'      "$FEATURE_ID"
    printf '## Packages (%s total)\n\n' "$(cap 'rpm -qa | wc -l')"
    printf '| Name | Version-Release | Vendor |\n'
    printf '|------|------------------|--------|\n'
    run_remote "rpm -qa --qf '%{NAME}|%{VERSION}-%{RELEASE}|%{VENDOR}\n' | sort" \
      | awk -F'|' 'NF>=3 {printf "| %s | %s | %s |\n", $1, $2, $3} NF<3 && NF>0 {printf "| %s |  |  |\n", $0}'
    printf '\n'
  } >"$APPENDIX_PKG"

  { section "Packages"; sub "Observations"; obs_header; } >>"$o"
  obs_row "total installed"    "$(cap 'rpm -qa | wc -l')"                                 "rpm -qa | wc -l"                 >>"$o"
  obs_row "vendor histogram"   "$(cap "rpm -qa --qf '%{VENDOR}\n' | sort | uniq -c | sort -rn | head -n 8")" "rpm -qa VENDOR histogram" >>"$o"
  obs_row "kernel/nvidia pkgs" "$(cap 'rpm -q kernel akmods kmod-nvidia 2>&1 || true')"   "rpm -q kernel akmods kmod-nvidia" >>"$o"
  obs_row "appendix"           "[${HOST_TAG}-${DATE_UTC}-packages.md](./${HOST_TAG}-${DATE_UTC}-packages.md)" "generated" >>"$o"

  printf '\n' >>"$o"
  sub "Findings" >>"$o"
  {
    findings_header
    local any=0
    local unfamiliar empty_vendor
    unfamiliar="$(run_remote "rpm -qa --qf '%{NAME}|%{VENDOR}\n' | awk -F'|' '\$2!~/(Fedora|RPM Fusion|redhat|Fedora Project)/ && \$2!=\"\" && \$2!=\"(none)\" {print \$1}' | sort -u" || true)"
    empty_vendor="$(cap "rpm -qa --qf '%{VENDOR}\n' | grep -c '^(none)$' || true")"

    if [ -n "$unfamiliar" ]; then
      # family counts (>5 → single summary row; otherwise individual rows)
      local fam_count
      fam_count() { printf '%s\n' "$unfamiliar" | grep -c "$1" || true; }
      local emit_item
      emit_item() {
        findings_row "$1" "non-Fedora/RPMFusion vendor" "investigate" "confirm intentional third-party package"
        any=1
      }
      local -A printed_family=()
      local fam pat
      local item
      for pair in "intel-oneapi:^intel-oneapi" "cuda:^cuda-" "nvidia:^nvidia-:^kmod-nvidia"; do
        fam="${pair%%:*}"; pat="${pair#*:}"
        local n
        n=$(printf '%s\n' "$unfamiliar" | grep -cE "$pat" || true)
        if [ "$n" -gt 5 ]; then
          emit_item "${fam}-* (${n} packages, grouped)"
          printed_family[$pat]=1
        fi
      done
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        local skip=0
        for printed_pat in "${!printed_family[@]}"; do
          if printf '%s' "$item" | grep -qE "$printed_pat"; then skip=1; break; fi
        done
        [ "$skip" -eq 1 ] && continue
        emit_item "$item"
      done <<< "$unfamiliar"
    fi
    if [ "${empty_vendor:-0}" != "0" ] && [ -n "$empty_vendor" ]; then
      findings_row "empty-vendor packages: ${empty_vendor}" "rpm vendor field '(none)'" "investigate" "includes NVIDIA CUDA 13.4 toolchain and other repo-less installs — enumerate before migration"
      any=1
    fi
    if [ "$any" -eq 0 ]; then printf 'none identified\n'; fi
  } >>"$o"
  log "[packages] done (appendix: $APPENDIX_PKG)"
}

collect_network() {
  NET_FILE="$(mktemp_domain)"
  local o="$NET_FILE"
  { section "Network"; sub "Observations"; obs_header; } >>"$o"

  obs_row "addresses"              "$(cap 'ip -brief address')"                            "ip -brief address"                 >>"$o"
  obs_row "links"                  "$(cap "ip -brief link | awk '{print \$1, \$2}'")"      "ip -brief link"                    >>"$o"
  obs_row "v4 routes"              "$(cap 'ip route')"                                     "ip route"                          >>"$o"
  obs_row "v6 routes"              "$(cap 'ip -6 route | head -n 6')"                      "ip -6 route"                       >>"$o"
  obs_row "resolv.conf"            "$(cap "grep -E '^(nameserver|search|domain)' /etc/resolv.conf")" "cat /etc/resolv.conf"    >>"$o"
  obs_row "listen sockets"         "$(cap "ss -tulnH 2>/dev/null | awk '{print \$1, \$5}' | sort -u")" "ss -tuln"            >>"$o"
  obs_row "listen process map"     "$(cap_marker "ss -tulpnH 2>/dev/null | grep users: | awk '{print \$1, \$5, \$7}' | sort -u | head -n 25" "not captured (no sudo)")" "ss -tulpn" >>"$o"
  obs_row "nmcli general"          "$(cap 'nmcli -t general status')"                      "nmcli general status"              >>"$o"
  obs_row "nmcli devices"          "$(cap 'nmcli -t device status | head -n 15')"          "nmcli device status"               >>"$o"
  obs_row "firewalld state"        "$(cap_marker 'firewall-cmd --state'                    "not captured (no sudo)")"          "firewall-cmd --state"            >>"$o"
  obs_row "firewalld default zone" "$(cap 'firewall-cmd --get-default-zone 2>/dev/null || true')" "firewall-cmd --get-default-zone" >>"$o"

  printf '\n' >>"$o"
  sub "Findings" >>"$o"
  {
    findings_header
    local any=0
    local exposed
    exposed="$(cap "ss -tulnH 2>/dev/null | awk '{print \$1, \$5}' | grep -E '(\\*:|:0\\.0\\.0\\.0|0\\.0\\.0\\.0:|\\[::\\]:)' | sort -u | head -n 40")"
    if [ -n "$exposed" ]; then
      local item
      local OLDIFS="$IFS"; IFS=';'
      for item in $exposed; do
        item="$(printf '%s' "$item" | tr -s ' ')"
        item="${item# }"; item="${item% }"
        [ -z "$item" ] && continue
        findings_row "listen: ${item}" "ss -tuln wildcard/internet-facing bind" "investigate" "justify exposure or bind to localhost"
        any=1
      done
      IFS="$OLDIFS"
    fi
    if [ "$any" -eq 0 ]; then printf 'none identified\n'; fi
  } >>"$o"
  log "[network] done"
}

collect_containers() {
  CTR_FILE="$(mktemp_domain)"
  local o="$CTR_FILE"
  section "Containers" >>"$o"
  sub "Observations" >>"$o"
  obs_header >>"$o"

  local detected
  detected="$(cap 'command -v podman docker 2>/dev/null')"
  obs_row "runtimes detected" "${detected:-none}" "command -v podman docker" >>"$o"

  if [ -z "$detected" ]; then
    printf '\n%s\n' "absent" >>"$o"
    log "[containers] absent (no runtime)"
    return 0
  fi

  case "$detected" in
    *podman*)
      obs_row "podman version"      "$(cap 'podman --version')"                                       "podman --version"                  >>"$o"
      obs_row "containers (ps -a)"  "$(cap "podman ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}'" )" "podman ps -a"                  >>"$o"
      obs_row "images (count)"      "$(cap 'podman images --format x 2>/dev/null | wc -l')"           "podman images | wc -l"             >>"$o"
      obs_row "images (top 10)"     "$(cap "podman images --format '{{.Repository}}:{{.Tag}} ({{.Size}})' | head -n 10")" "podman images" >>"$o"
      obs_row "podman networks"     "$(cap "podman network ls --format '{{.Name}} {{.Driver}}'")"     "podman network ls"                 >>"$o"
      obs_row "podman volumes"      "$(cap 'podman volume ls --format x 2>/dev/null | wc -l')"        "podman volume ls | wc -l"          >>"$o"
      ;;
  esac
  case "$detected" in
    *docker*)
      obs_row "docker ps -a" "$(cap_marker "docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}'" "not captured (no sudo)")" "docker ps -a" >>"$o"
      ;;
  esac

  printf '\n' >>"$o"
  sub "Findings" >>"$o"
  {
    findings_header
    local any=0
    if printf '%s' "$detected" | grep -q podman; then
      local exited dangling item
      exited="$(cap "podman ps -a --filter status=exited --format '{{.Names}} ({{.Status}})'")"
      dangling="$(cap "podman images -f dangling=true --format '{{.ID}}'")"
      if [ -n "$exited" ]; then
        local OLDIFS="$IFS"; IFS=';'
        for item in $exited; do
          item="${item# }"; item="${item% }"
          [ -z "$item" ] && continue
          findings_row "exited: $item" "podman ps --filter status=exited" "investigate" "restart, keep, or remove"
          any=1
        done
        IFS="$OLDIFS"
      fi
      if [ -n "$dangling" ]; then
        local OLDIFS="$IFS"; IFS=';'
        for item in $dangling; do
          item="${item# }"; item="${item% }"
          [ -z "$item" ] && continue
          findings_row "dangling-image: $item" "podman images -f dangling=true" "investigate" "candidate for image prune"
          any=1
        done
        IFS="$OLDIFS"
      fi
    fi
    if [ "$any" -eq 0 ]; then printf 'none identified\n'; fi
  } >>"$o"
  log "[containers] done"
}

collect_services() {
  SVC_FILE="$(mktemp_domain)"
  local o="$SVC_FILE"

  # Services appendix — full unit lists (FR-006 requires enumeration, not just counts)
  {
    printf '# Services — %s — %s\n\n' "$HOST_TAG" "$(date -u +%F)"
    printf '## Snapshot\n\n'
    printf -- '- Hostname: `%s`\n'          "$HOST_TAG"
    printf -- '- FQDN: `%s`\n'              "$(cap 'hostname -f')"
    printf -- '- Captured at (UTC): `%s`\n' "$CAPTURED_AT"
    printf -- '- Operator: `%s`\n'          "$OPERATOR"
    printf -- '- Project git ref: `%s`\n'   "$GIT_REF"
    printf -- '- Feature ID: `%s`\n\n'      "$FEATURE_ID"

    printf '## Enabled services — system (%s units)\n\n' "$(cap 'systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null | wc -l')"
    printf '```\n'
    run_remote 'systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null' || true
    printf '```\n\n'

    printf '## Running services — system (%s units)\n\n' "$(cap 'systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l')"
    printf '```\n'
    run_remote 'systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null' || true
    printf '```\n\n'

    printf '## Failed services — system (%s units)\n\n' "$(cap 'systemctl --failed --no-pager --no-legend 2>/dev/null | wc -l')"
    printf '```\n'
    run_remote 'systemctl --failed --no-pager --no-legend 2>/dev/null' || true
    printf '```\n\n'

    printf '## Enabled services — user (%s units)\n\n' "$(cap 'systemctl --user list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null | wc -l')"
    printf '```\n'
    run_remote 'systemctl --user list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null' || true
    printf '```\n\n'

    printf '## Running services — user (%s units)\n\n' "$(cap 'systemctl --user list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l')"
    printf '```\n'
    run_remote 'systemctl --user list-units --type=service --state=running --no-pager --no-legend 2>/dev/null' || true
    printf '```\n\n'

    printf '## Failed services — user\n\n'
    printf '```\n'
    run_remote 'systemctl --user --failed --no-pager --no-legend 2>/dev/null' || true
    printf '```\n'
  } >"$APPENDIX_SVC"

  { section "Services"; sub "Observations"; obs_header; } >>"$o"

  obs_row "enabled (system)"   "$(cap 'systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null | wc -l')" "systemctl (enabled, system)" >>"$o"
  obs_row "running (system)"   "$(cap 'systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l')"     "systemctl (running, system)" >>"$o"
  obs_row "failed (system)"    "$(cap 'systemctl --failed --no-pager --no-legend 2>/dev/null | wc -l')"                                      "systemctl (failed, system)"  >>"$o"
  obs_row "failed units (sys)" "$(cap "systemctl --failed --no-pager --no-legend 2>/dev/null | awk '{print \$2}'")"                          "systemctl --failed (names)"  >>"$o"
  obs_row "enabled (user)"     "$(cap_marker 'systemctl --user list-unit-files --type=service --state=enabled --no-pager --no-legend 2>/dev/null | wc -l' "not captured (user systemd unavailable)")" "systemctl --user (enabled)" >>"$o"
  obs_row "running (user)"     "$(cap_marker 'systemctl --user list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l' "not captured (user systemd unavailable)")" "systemctl --user (running)" >>"$o"
  obs_row "failed (user)"      "$(cap_marker "systemctl --user --failed --no-pager --no-legend 2>/dev/null | awk '{print \$2}'" "not captured (user systemd unavailable)")" "systemctl --user --failed" >>"$o"
  obs_row "full unit lists"    "[${HOST_TAG}-${DATE_UTC}-services.md](./${HOST_TAG}-${DATE_UTC}-services.md)" "generated" >>"$o"

  printf '\n' >>"$o"
  sub "Findings" >>"$o"
  {
    findings_header
    local any=0
    local failed_sys failed_usr item
    failed_sys="$(cap "systemctl --failed --no-pager --no-legend 2>/dev/null | awk '{print \$2}'")"
    failed_usr="$(cap "systemctl --user --failed --no-pager --no-legend 2>/dev/null | awk '{print \$2}'")"
    if [ -n "$failed_sys" ]; then
      local OLDIFS="$IFS"; IFS=';'
      for item in $failed_sys; do
        item="${item# }"; item="${item% }"
        [ -z "$item" ] && continue
        findings_row "system-failed: $item" "systemctl --failed" "investigate" "resolve or disable before migration"
        any=1
      done
      IFS="$OLDIFS"
    fi
    if [ -n "$failed_usr" ]; then
      local OLDIFS="$IFS"; IFS=';'
      for item in $failed_usr; do
        item="${item# }"; item="${item% }"
        [ -z "$item" ] && continue
        findings_row "user-failed: $item" "systemctl --user --failed" "investigate" "resolve or disable before migration"
        any=1
      done
      IFS="$OLDIFS"
    fi
    if [ "$any" -eq 0 ]; then printf 'none identified\n'; fi
  } >>"$o"
  log "[services] done"
}

collect_vms() {
  VM_FILE="$(mktemp_domain)"
  local o="$VM_FILE"
  section "Virtual Machines" >>"$o"
  sub "Observations" >>"$o"
  obs_header >>"$o"

  local virsh_path
  virsh_path="$(cap 'command -v virsh 2>/dev/null')"
  obs_row "virsh" "${virsh_path:-not-installed}" "command -v virsh" >>"$o"

  if [ -z "$virsh_path" ]; then
    printf '\n%s\n' "absent" >>"$o"
    log "[vms] absent (no libvirt)"
    return 0
  fi

  obs_row "domains (detail)"      "$(cap 'virsh list --all 2>&1 | tail -n +3 | grep -v "^[[:space:]]*$" || true')" "virsh list --all" >>"$o"
  obs_row "domains (total)"       "$(cap 'virsh list --all --name 2>/dev/null | grep -c . || true')"             "virsh list --all --name | wc -l" >>"$o"
  obs_row "domains (running)"     "$(cap 'virsh list --name 2>/dev/null | grep -c . || true')"                   "virsh list --name | wc -l" >>"$o"
  obs_row "libvirt networks"      "$(cap_marker 'virsh net-list --all --name 2>/dev/null' "not captured (no sudo)")" "virsh net-list --all" >>"$o"
  obs_row "libvirt pools"         "$(cap_marker 'virsh pool-list --all --name 2>/dev/null' "not captured (no sudo)")" "virsh pool-list --all" >>"$o"

  printf '\n' >>"$o"
  sub "Findings" >>"$o"
  {
    findings_header
    local any=0
    local inactive item
    inactive="$(cap 'virsh list --all --inactive --name 2>/dev/null')"
    if [ -n "$inactive" ]; then
      local OLDIFS="$IFS"; IFS=';'
      for item in $inactive; do
        item="${item# }"; item="${item% }"
        [ -z "$item" ] && continue
        findings_row "defined-inactive-vm: $item" "virsh list --all --inactive --name" "investigate" "keep/remove/migrate before bootc cut-over"
        any=1
      done
      IFS="$OLDIFS"
    fi
    if [ "$any" -eq 0 ]; then printf 'none identified\n'; fi
  } >>"$o"
  log "[vms] done"
}

collect_repo_artifacts() {
  REPO_FILE="$(mktemp_domain)"
  local o="$REPO_FILE"
  section "Repo Artifacts" >>"$o"
  printf 'Reviewer pass (task T017) converts each `TODO` disposition to a terminal value.\n\n' >>"$o"
  printf '| Path | Category | Disposition | Reviewer note |\n' >>"$o"
  printf '|------|----------|-------------|---------------|\n' >>"$o"

  local row path catg disp note
  while IFS='|' read -r path catg disp note; do
    [ -z "$path" ] && continue
    printf '| `%s` | %s | %s | %s |\n' "$path" "$catg" "$disp" "$note" >>"$o"
  done <<'ROWS'
installer.yaml|ansible|TODO|
install-gcc-13.yaml|ansible|TODO|
cuda-install.sh|script|TODO|
scripts/granite-20.sh|script|TODO|
nvidia-driver.md|doc|TODO|
hard-to-automate.md|doc|TODO|
thunderbird.md|doc|TODO|
bash_profile|dotfile|TODO|
bashrc|dotfile|TODO|
gpg-agent.conf|dotfile|TODO|
gpg.conf|dotfile|TODO|
ssh-config|dotfile|TODO|
bootc/Containerfile|image-def|TODO|
specs/|doc|TODO|
.specify/|doc|TODO|
inventory.yaml|ansible|TODO|
requirements.txt|config|TODO|
pyproject.toml|config|TODO|
commitlint.config.js|config|TODO|
CHANGELOG.md|doc|TODO|
README.md|doc|TODO|
LICENSE|doc|TODO|
ROWS
  log "[repo-artifacts] emitted"
}

# --- Renderer -----------------------------------------------------------------

render_main_report() {
  {
    printf '# State Snapshot — %s — %s\n\n' "$HOST_TAG" "$(date -u +%F)"

    section "Snapshot"
    printf -- '- Hostname: `%s`\n'          "$(cap 'hostname')"
    printf -- '- FQDN: `%s`\n'              "$(cap 'hostname -f')"
    printf -- '- Captured at (UTC): `%s`\n' "$CAPTURED_AT"
    printf -- '- Operator: `%s`\n'          "$OPERATOR"
    printf -- '- Project git ref: `%s`\n'   "$GIT_REF"
    printf -- '- Feature ID: `%s`\n\n'      "$FEATURE_ID"
    printf -- 'Capture policy: read-only, unprivileged (no sudo), no remote writes.\n\n'

    cat "$HOST_FILE";  printf '\n'
    cat "$PKG_FILE";   printf '\n'
    cat "$NET_FILE";   printf '\n'
    cat "$CTR_FILE";   printf '\n'
    cat "$SVC_FILE";   printf '\n'
    cat "$VM_FILE";    printf '\n'
    cat "$REPO_FILE";  printf '\n'

    section "Provenance"
    printf '| # | Side | Command | Exit | Sudo | Timestamp (UTC) |\n'
    printf '|---|------|---------|------|------|------------------|\n'
    cat "$PROV_FILE"
    printf '\n'
  } >"$MAIN_REPORT"

  local lines
  lines=$(wc -l <"$MAIN_REPORT" | tr -d ' ')
  if [ "$lines" -gt 800 ]; then
    warn "main report is ${lines} lines (ceiling 800)"
  else
    log "[render] main report ${lines} lines: ${MAIN_REPORT}"
  fi
}

cleanup_temp() {
  rm -f "$HOST_FILE" "$NET_FILE" "$PKG_FILE" "$CTR_FILE" "$SVC_FILE" "$VM_FILE" "$REPO_FILE" "$PROV_FILE" 2>/dev/null || true
  ssh "${SSH_OPTS[@]}" -O exit "$HOST" >/dev/null 2>&1 || true
}
trap cleanup_temp EXIT

# --- Main ---------------------------------------------------------------------

main() {
  if [ "$DRY_RUN" -eq 1 ]; then
    dry_run
  fi

  check_preconditions

  collect_host_context
  collect_packages
  collect_network
  collect_containers
  collect_services
  collect_vms
  collect_repo_artifacts
  render_main_report

  log "[done] capture complete"
  log "  main:     ${MAIN_REPORT}"
  log "  appendix: ${APPENDIX_PKG}"
}

main
