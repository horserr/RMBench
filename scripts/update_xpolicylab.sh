#!/usr/bin/env bash
# Clone or refresh the XPolicyLab checkout that RMBench evaluates against.
#
# XPolicyLab is no longer a git submodule; it lives in a separate repository
# located through XPOLICYLAB_ROOT (default: a sibling "XPolicyLab" directory
# next to this repository). This script keeps that checkout pinned to the
# revision RMBench is tested against.
#
# Usage:
#   bash scripts/update_xpolicylab.sh
#   bash scripts/update_xpolicylab.sh --install
#
# Environment:
#   XPOLICYLAB_ROOT   override the checkout location
#   XPOLICYLAB_URL    override the clone URL (default: horserr/XPolicyLab)
#   XPOLICYLAB_REV    override the pinned revision
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RMBENCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

XPOLICYLAB_URL="${XPOLICYLAB_URL:-https://github.com/horserr/XPolicyLab.git}"
XPOLICYLAB_REV="${XPOLICYLAB_REV:-800f7e1a4a9a44b4f827b241a34025cc43dcbd70}"
XPOLICYLAB_ROOT="${XPOLICYLAB_ROOT:-${RMBENCH_ROOT}/../XPolicyLab}"

DO_INSTALL=0

usage() {
    cat <<'EOF'
Usage: bash scripts/update_xpolicylab.sh [options]

Clone (or refresh) the standalone XPolicyLab checkout pinned to XPOLICYLAB_REV.

Options:
  --install   pip install -e the checkout after a successful update
  -h, --help  show this help

Environment:
  XPOLICYLAB_ROOT  checkout location (default: sibling ../XPolicyLab)
  XPOLICYLAB_URL   clone URL (default: horserr/XPolicyLab)
  XPOLICYLAB_REV   pinned revision
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            DO_INSTALL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[XPolicyLab][ERROR] Unexpected argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -e "${XPOLICYLAB_ROOT}/.git" ]]; then
    echo "[XPolicyLab] Cloning ${XPOLICYLAB_URL} into ${XPOLICYLAB_ROOT} ..."
    git clone "${XPOLICYLAB_URL}" "${XPOLICYLAB_ROOT}"
fi

echo "[XPolicyLab] Fetching pinned revision ${XPOLICYLAB_REV:0:7} ..."
git -C "${XPOLICYLAB_ROOT}" fetch --prune origin
git -C "${XPOLICYLAB_ROOT}" checkout --detach "${XPOLICYLAB_REV}"

if [[ ! -f "${XPOLICYLAB_ROOT}/setup_policy_server.py" ]]; then
    echo "[XPolicyLab][ERROR] Checkout is missing setup_policy_server.py; update aborted." >&2
    exit 1
fi

commit_short="$(git -C "${XPOLICYLAB_ROOT}" rev-parse --short HEAD)"
subject="$(git -C "${XPOLICYLAB_ROOT}" log -1 --pretty=%s)"
echo "[XPolicyLab] Ready at ${commit_short} — ${subject}"

robot_info="${XPOLICYLAB_ROOT}/utils/robot/_robot_info.json"
if [[ -f "${robot_info}" ]] && ! grep -q '"arx_x5"' "${robot_info}"; then
    echo "[XPolicyLab][WARN] This revision does not define the arx_x5 action profile." >&2
    echo "[XPolicyLab][WARN] Select another compatible profile in the RMBench eval config." >&2
fi

if [[ "${DO_INSTALL}" -eq 1 ]]; then
    echo "[XPolicyLab] Installing editable package into the current Python environment..."
    python -m pip install -e "${XPOLICYLAB_ROOT}"
fi
