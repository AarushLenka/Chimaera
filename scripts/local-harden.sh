#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
librelane_venv="${LIBRELANE_VENV:-${HOME}/.venv/librelane}"
pdk_root="${PDK_ROOT:-}"

if [[ ! -x "$librelane_venv/bin/librelane" ]]; then
  echo "LibreLane not found at $librelane_venv" >&2
  echo "Set LIBRELANE_VENV to the local LibreLane virtualenv." >&2
  exit 2
fi

if [[ -z "$pdk_root" || ! -d "$pdk_root/ihp-sg13cmos5l" ]]; then
  echo "IHP SG13C5L PDK not found." >&2
  echo "Set PDK_ROOT to the Ciel version directory containing ihp-sg13cmos5l/." >&2
  echo "The required path can be obtained with:" >&2
  echo "  ciel path --pdk ihp-sg13g2 \"\$(ciel output --pdk ihp-sg13g2)\"" >&2
  exit 2
fi

for tool in yosys openroad klayout magic; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required native hardening tool not found: $tool" >&2
    exit 2
  fi
done

cd "$repo_dir"
exec "$librelane_venv/bin/librelane" \
  --manual-pdk \
  --pdk-root "$pdk_root" \
  --pdk ihp-sg13cmos5l \
  --design-dir "$repo_dir" \
  --flow classic \
  --run-tag chimaera-local \
  --overwrite \
  --jobs "${LIBRELANE_JOBS:-12}" \
  "$repo_dir/config.local.json"
