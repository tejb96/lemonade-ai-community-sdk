#!/usr/bin/env bash
# Vendor the Workshop snap for sdkcraft test (private snap; not committed to git).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="${ROOT}/tests"

cd "${TESTS}"
rm -f workshop.snap
snap download workshop
chown "$(whoami):$(whoami)" workshop_*.snap

snap_file="$(echo workshop_*.snap)"
if ! file "${snap_file}" | grep -q 'Squashfs filesystem'; then
  echo "error: ${snap_file} is not a Squashfs snap (got: $(file -b "${snap_file}"))" >&2
  exit 1
fi

echo "Prepared ${TESTS}/${snap_file}"
