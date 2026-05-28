#!/usr/bin/env bash
# Sync sdkcraft.yaml version: from the repo-root VERSION file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT}/VERSION")"

if [[ -z "${VERSION}" ]]; then
  echo "VERSION file is empty" >&2
  exit 1
fi

sed -i "s/^version:.*/version: \"${VERSION}\"/" "${ROOT}/sdkcraft.yaml"
echo "[sync-version] sdkcraft.yaml version set to ${VERSION}"
