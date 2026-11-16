#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version (Keep a Changelog format).
# Exits non-zero when the section is missing or empty.
#
# Usage: Scripts/changelog-section.sh 0.1.0 [CHANGELOG.md]
set -euo pipefail

version="${1:?usage: changelog-section.sh <version> [file]}"
file="${2:-CHANGELOG.md}"

section="$(awk -v header="## [${version}]" '
  index($0, header) == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found && !/^\[[^]]+\]: / { print }
' "$file")"

if [[ -z "${section//[[:space:]]/}" ]]; then
  echo "No CHANGELOG entry for ${version} in ${file}" >&2
  exit 1
fi

printf '%s\n' "$section"
