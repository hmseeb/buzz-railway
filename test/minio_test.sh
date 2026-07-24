#!/usr/bin/env bash
# Contract for the MinIO companion image.
#
# Upstream's minio image starts nothing useful without arguments, and the bucket
# has to exist before Buzz will talk to it. Railway's CLI cannot set a start
# command, so both of those are baked into this image instead of the template.
#
# Usage: ./test/minio_test.sh [image-tag]
set -uo pipefail

IMG="${1:-buzz-railway-minio:test}"
NAME="minio-contract-test-$$"
PORT=19000
PW="test-secret-$$"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  printf '        expected: %s\n' "$2"
  printf '        actual:   %s\n' "$3"
  FAILED=1
}

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "minio_test: $IMG"

docker run -d --name "$NAME" \
  -e MINIO_ROOT_USER=buzz \
  -e MINIO_ROOT_PASSWORD="$PW" \
  -e BUZZ_S3_BUCKET=buzz-media \
  -e PORT=$PORT \
  -p "$PORT:$PORT" "$IMG" >/dev/null 2>&1

# 1. Starts a server with no arguments supplied by the platform.
health=""
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/minio/health/live" 2>/dev/null)
  if [[ "$code" == "200" ]]; then health=ok; break; fi
  sleep 1
done
if [[ "$health" == "ok" ]]; then
  pass "serves on \$PORT with no start command"
else
  fail "serves on \$PORT with no start command" "health endpoint returning 200" \
       "$(docker logs "$NAME" 2>&1 | tail -5)"
fi

# 2. The bucket Buzz expects must already exist, or media and git object writes
#    fail on a relay that otherwise looks healthy.
# The bucket is created after the server answers its health check, so this has
# to poll rather than check once — a single check passes or fails on timing.
# docker exec does not inherit the entrypoint's environment either, so the mc
# config directory has to be passed again or mc falls back to a default alias
# pointing at :9000.
buckets=""
for _ in $(seq 1 20); do
  buckets=$(docker exec -e MC_CONFIG_DIR=/tmp/.mc "$NAME" mc ls local 2>&1)
  [[ "$buckets" == *buzz-media* ]] && break
  sleep 1
done
if [[ "$buckets" == *buzz-media* ]]; then
  pass "creates the buzz-media bucket on first boot"
else
  fail "creates the buzz-media bucket on first boot" "a bucket named buzz-media" "$buckets"
fi

# 3. Buzz hardcodes path-style S3 addressing, so the bucket has to be reachable
#    at /<bucket> rather than as a host prefix.
code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/buzz-media/" 2>/dev/null)
if [[ "$code" == "403" || "$code" == "200" ]]; then
  pass "answers path-style requests for the bucket (HTTP $code)"
else
  fail "answers path-style requests for the bucket" "403 or 200" "HTTP $code"
fi

echo
if [[ $FAILED -eq 0 ]]; then
  echo "minio_test: PASS"
else
  echo "minio_test: FAIL"
fi
exit $FAILED
