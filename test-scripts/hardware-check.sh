#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/.." && pwd)"

host="${HW_CHECK_HOST:-}"
ssh_port="${HW_CHECK_SSH_PORT:-22}"
stamp="$(date -u +%Y%m%d%H%M%S)"
remote_runner="/tmp/box-hardware-check-${stamp}.sh"
remote_tarball=""
local_out_dir="${ROOT_DIR}/output/hardware-tests"
local_tarball="${local_out_dir}/hardware-check-${stamp}.tar.gz"
ssh_reuse_dir=""
ssh_control_path=""
ssh_deploy_key=""
ssh_deploy_pubkey=""
remote_key_installed=no

usage() {
  cat <<'EOF'
usage: test-scripts/hardware-check.sh

Copy the hardware check runner to the box over SSH, execute it, and pull the
resulting log archive into output/hardware-tests/.

Environment:
  HW_CHECK_HOST          SSH target, for example root@192.168.1.50
  HW_CHECK_SSH_PORT      SSH port, default: 22
  HW_CHECK_SSH_KEY       Existing SSH private key to use, optional
  HW_CHECK_SKIP_TEMP_KEY Pass yes to skip temporary key install, default: no
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$host" ]]; then
  echo "Set HW_CHECK_HOST to the box SSH target, for example root@192.168.1.50." >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

shell_quote() {
  printf '%q' "$1"
}

require_cmd ssh
require_cmd scp
if [[ -z "${HW_CHECK_SSH_KEY:-}" && "${HW_CHECK_SKIP_TEMP_KEY:-no}" != "yes" ]]; then
  require_cmd ssh-keygen
fi

mkdir -p "$local_out_dir"

ssh_opts=(
  -p "$ssh_port"
  -o ConnectTimeout=10
  -o ConnectionAttempts=3
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=6
  -o TCPKeepAlive=yes
)
scp_opts=(
  -P "$ssh_port"
  -o ConnectTimeout=10
  -o ConnectionAttempts=3
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=6
  -o TCPKeepAlive=yes
)

if [[ -n "${HW_CHECK_SSH_KEY:-}" ]]; then
  ssh_opts=(-i "$HW_CHECK_SSH_KEY" "${ssh_opts[@]}")
  scp_opts=(-i "$HW_CHECK_SSH_KEY" "${scp_opts[@]}")
fi

remove_remote_deploy_key() {
  local quoted_key

  if [[ "$remote_key_installed" == "yes" && -n "$ssh_deploy_pubkey" ]]; then
    quoted_key="$(shell_quote "$ssh_deploy_pubkey")"
    ssh "${ssh_opts[@]}" "$host" "PUBKEY=$quoted_key bash -s" <<'EOF' >/dev/null 2>&1 || true
set -euo pipefail
auth=/root/.ssh/authorized_keys
tmp=/root/.ssh/authorized_keys.tmp
if [[ -f "$auth" ]]; then
  grep -vxF "$PUBKEY" "$auth" >"$tmp" || true
  cat "$tmp" >"$auth"
  rm -f "$tmp"
  chmod 0600 "$auth"
fi
EOF
    remote_key_installed=no
  fi
}

cleanup_remote() {
  if [[ -n "$remote_tarball" ]]; then
    ssh "${ssh_opts[@]}" "$host" "rm -f '$remote_runner' '$remote_tarball'" >/dev/null 2>&1 || true
  else
    ssh "${ssh_opts[@]}" "$host" "rm -f '$remote_runner'" >/dev/null 2>&1 || true
  fi
}

cleanup_ssh_reuse() {
  cleanup_remote
  remove_remote_deploy_key

  if [[ -n "$ssh_control_path" ]]; then
    ssh "${ssh_opts[@]}" -O exit "$host" >/dev/null 2>&1 || true
  fi

  if [[ -n "$ssh_reuse_dir" ]]; then
    rm -rf "$ssh_reuse_dir"
  fi
}

setup_ssh_reuse() {
  local quoted_key

  ssh_reuse_dir="$(mktemp -d /tmp/isg-hw-ssh-reuse.XXXXXX)"
  ssh_control_path="$ssh_reuse_dir/control-%C"

  ssh_opts=(
    -o ControlMaster=auto
    -o ControlPersist=10m
    -o ControlPath="$ssh_control_path"
    "${ssh_opts[@]}"
  )
  scp_opts=(
    -o ControlMaster=auto
    -o ControlPersist=10m
    -o ControlPath="$ssh_control_path"
    "${scp_opts[@]}"
  )

  trap cleanup_ssh_reuse EXIT

  echo "Opening reusable SSH connection to $host."
  ssh "${ssh_opts[@]}" -MNf "$host"

  if [[ -n "${HW_CHECK_SSH_KEY:-}" || "${HW_CHECK_SKIP_TEMP_KEY:-no}" == "yes" ]]; then
    return
  fi

  ssh_deploy_key="$ssh_reuse_dir/deploy-key"
  ssh-keygen -q -t ed25519 -N "" -f "$ssh_deploy_key" -C "isg-hw-check-${stamp}"

  echo "Installing temporary hardware-check key for follow-up SSH operations."
  ssh_deploy_pubkey="$(<"$ssh_deploy_key.pub")"
  quoted_key="$(shell_quote "$ssh_deploy_pubkey")"
  ssh "${ssh_opts[@]}" "$host" "PUBKEY=$quoted_key bash -s" <<'EOF'
set -euo pipefail
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
grep -qxF "$PUBKEY" /root/.ssh/authorized_keys || printf '%s\n' "$PUBKEY" >>/root/.ssh/authorized_keys
EOF
  remote_key_installed=yes
  ssh_opts=(-i "$ssh_deploy_key" "${ssh_opts[@]}")
  scp_opts=(-i "$ssh_deploy_key" "${scp_opts[@]}")
}

setup_ssh_reuse

scp "${scp_opts[@]}" "${SELF_DIR}/box-hardware-check.sh" "${host}:${remote_runner}"
ssh "${ssh_opts[@]}" "$host" "chmod 0755 '$remote_runner'"

echo "Running hardware check on ${host}..."
remote_tarball="$(ssh "${ssh_opts[@]}" "$host" "'$remote_runner' '$stamp'" | tail -n 1)"

if [[ -z "$remote_tarball" ]]; then
  echo "Remote hardware check did not return a tarball path." >&2
  exit 1
fi

scp "${scp_opts[@]}" "${host}:${remote_tarball}" "$local_tarball"

echo "Hardware check archive: $local_tarball"
