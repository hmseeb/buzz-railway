#!/usr/bin/env bash
# Contract for the image version tag.
#
# CI publishes each image as :<version> read from the Dockerfile's
# org.opencontainers.image.version label, and the template pins that tag. The
# version must start with the upstream release in the FROM line, plus -r<N>
# for our own rebuilds, so a tag always says which upstream it ships.
#
# Usage: ./test/version_test.sh [Dockerfile ...]
set -uo pipefail
cd "$(dirname "$0")/.."

FAILED=0
files=("$@")
[[ ${#files[@]} -eq 0 ]] && files=(Dockerfile Dockerfile.minio)

for f in "${files[@]}"; do
  # Last FROM is the runtime stage; earlier ones are build stages.
  from=$(grep -E '^FROM ' "$f" | tail -1 | awk '{print $2}')
  ref=${from%%@*}
  upstream=${ref##*:}
  version=$(grep -oE 'org\.opencontainers\.image\.version="[^"]+"' "$f" | cut -d'"' -f2)
  if [[ "$ref" != *:* || "$upstream" == latest || "$upstream" == main ]]; then
    printf '  FAIL  %s: FROM must name an upstream release tag, got %s\n' "$f" "$from"
    FAILED=1
  elif [[ ! "$version" =~ ^${upstream//./\\.}-r[0-9]+$ ]]; then
    printf '  FAIL  %s: version label %q must be %s-r<N>\n' "$f" "$version" "$upstream"
    FAILED=1
  else
    printf '  ok    %s -> %s\n' "$f" "$version"
  fi
done

if [[ $FAILED -eq 0 ]]; then echo "version_test: PASS"; else echo "version_test: FAIL"; fi
exit $FAILED
