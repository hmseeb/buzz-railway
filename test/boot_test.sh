#!/usr/bin/env bash
# Contract for the buzz-boot entrypoint.
#
# The bootstrap exists because buzz-relay silently ignores unknown argv and
# warn-and-ignores an invalid RELAY_OWNER_PUBKEY. Both failures produce a
# running relay that nobody can administer, with nothing useful in the logs.
# These four cases are the ones that would ship that broken deploy.
#
# Usage: ./test/boot_test.sh [image-tag]
set -uo pipefail

IMG="${1:-buzz-railway:test}"
VOL="buzz-boot-test-$$"
HEX64="1111111111111111111111111111111111111111111111111111111111111111"
FAILED=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  printf '        expected: %s\n' "$2"
  printf '        actual:   %s\n' "$3"
  FAILED=1
}

cleanup() { docker volume rm -f "$VOL" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Runs the image with `env` as the command so we can read what the bootstrap
# exported without starting a relay (and without needing a database).
run_env() { docker run --rm -v "$VOL:/data/git" "$@" "$IMG" env 2>&1; }

owner_of() { grep -oE '^RELAY_OWNER_PUBKEY=.*' <<<"$1" | cut -d= -f2; }

echo "boot_test: $IMG"

# 1. No pubkey supplied: bootstrap must mint one so the deploy is usable
#    without the operator already owning a Nostr identity.
out=$(run_env)
generated=$(owner_of "$out")
if [[ "$generated" =~ ^[0-9a-f]{64}$ ]]; then
  pass "generates a valid owner pubkey when none is supplied"
else
  fail "generates a valid owner pubkey when none is supplied" \
       "RELAY_OWNER_PUBKEY matching ^[0-9a-f]{64}$" "${generated:-<unset>}"
fi

# 2. Same volume, second boot: the owner must not change. A fresh key on every
#    restart would lock the operator out of their own relay.
second=$(owner_of "$(run_env)")
if [[ -n "$generated" && "$second" == "$generated" ]]; then
  pass "reuses the persisted owner pubkey across restarts"
else
  fail "reuses the persisted owner pubkey across restarts" \
       "$generated" "${second:-<unset>}"
fi

# 3. Operator supplies their own pubkey: pass through untouched.
supplied=$(owner_of "$(run_env -e "RELAY_OWNER_PUBKEY=$HEX64")")
if [[ "$supplied" == "$HEX64" ]]; then
  pass "passes a supplied pubkey through unchanged"
else
  fail "passes a supplied pubkey through unchanged" "$HEX64" "${supplied:-<unset>}"
fi

# 4. Operator pastes an npub (what a human actually has) instead of hex. The
#    relay would warn and ignore it, leaving an unadministrable deploy, so the
#    bootstrap must refuse to start.
# The relay's own warn-and-ignore message also contains the word "hex", so this
# asserts on the buzz-boot prefix too — otherwise it passes on the very failure
# it exists to prevent.
bad=$(docker run --rm -v "$VOL:/data/git" -e "RELAY_OWNER_PUBKEY=npub1abc" "$IMG" env 2>&1)
code=$?
if [[ $code -ne 0 && "$bad" == *buzz-boot:* && "$bad" == *hex* ]]; then
  pass "rejects a non-hex pubkey before the relay starts"
else
  fail "rejects a non-hex pubkey before the relay starts" \
       "non-zero exit, message prefixed buzz-boot: and mentioning hex" \
       "exit=$code out=$bad"
fi

echo
if [[ $FAILED -eq 0 ]]; then
  echo "boot_test: PASS"
else
  echo "boot_test: FAIL"
fi
exit $FAILED
