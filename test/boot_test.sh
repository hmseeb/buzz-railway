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

# 5. Railway mounts volumes owned by root while the relay runs as uid 1000, so
#    a plain named volume (which inherits image ownership) does not reproduce
#    production. A root-owned tmpfs does. The bootstrap has to fix ownership and
#    still hand off unprivileged.
root_vol=$(docker run --rm --tmpfs /data/git:uid=0,gid=0,mode=0755 "$IMG" \
  sh -c 'echo "UID=$(id -u)"; env' 2>&1)
root_owner=$(owner_of "$root_vol")
if [[ "$root_vol" == *"UID=1000"* && "$root_owner" =~ ^[0-9a-f]{64}$ ]]; then
  pass "works on a root-owned volume and drops back to uid 1000"
else
  fail "works on a root-owned volume and drops back to uid 1000" \
       "UID=1000 and a 64-hex owner pubkey" "$root_vol"
fi

# 6. A bind address with an empty port is what you get when a platform variable
#    reference resolves to nothing. The relay rejects it and crash-loops, so the
#    bootstrap repairs it from $PORT instead.
bind=$(run_env -e "BUZZ_BIND_ADDR=0.0.0.0:" -e "PORT=3000" | grep -oE '^BUZZ_BIND_ADDR=.*' | cut -d= -f2)
if [[ "$bind" == "0.0.0.0:3000" ]]; then
  pass "repairs a bind address with an empty port from \$PORT"
else
  fail "repairs a bind address with an empty port from \$PORT" "0.0.0.0:3000" "${bind:-<unset>}"
fi

# 7. An explicit, well-formed bind address must survive untouched.
kept=$(run_env -e "BUZZ_BIND_ADDR=0.0.0.0:9999" -e "PORT=3000" | grep -oE '^BUZZ_BIND_ADDR=.*' | cut -d= -f2)
if [[ "$kept" == "0.0.0.0:9999" ]]; then
  pass "leaves an explicit bind address alone"
else
  fail "leaves an explicit bind address alone" "0.0.0.0:9999" "${kept:-<unset>}"
fi

# 8. Railway injects its own PORT and it overrides the image's ENV. When that
#    value is 8080 it collides with the relay's default health port and the
#    process dies on "Address already in use", after a clean startup that makes
#    it look like a networking fault.
hp=$(run_env -e "PORT=8080" | grep -oE '^BUZZ_HEALTH_PORT=.*' | cut -d= -f2)
bind8080=$(run_env -e "PORT=8080" | grep -oE '^BUZZ_BIND_ADDR=.*' | cut -d= -f2)
if [[ "$bind8080" == "0.0.0.0:8080" && -n "$hp" && "$hp" != "8080" ]]; then
  pass "moves the health port when \$PORT would collide with it (-> $hp)"
else
  fail "moves the health port when \$PORT would collide with it" \
       "bind 0.0.0.0:8080 and a health port other than 8080" \
       "bind=$bind8080 health=${hp:-<unset>}"
fi

# 9. One deploy, many workspaces: the relay resolves communities by hostname,
#    but provisioning is gated by RELAY_OPERATOR_PUBKEYS and an empty allowlist
#    disables it entirely. The owner should be an operator by default, or a
#    deployer can never add a second community without editing variables.
op=$(run_env | grep -oE '^RELAY_OPERATOR_PUBKEYS=.*' | cut -d= -f2)
own=$(owner_of "$(run_env)")
if [[ -n "$op" && "$op" =~ ^[0-9a-f]{64}$ ]]; then
  pass "makes the generated owner a relay operator by default"
else
  fail "makes the generated owner a relay operator by default" \
       "RELAY_OPERATOR_PUBKEYS set to a 64-hex pubkey" "${op:-<unset>}"
fi

# 9b. Provisioning also needs RELAY_OPERATOR_API_ORIGIN, or the endpoint 500s
#     with "operator API origin is not configured" — being an operator is not
#     enough on its own. Derive it from the platform's public domain.
origin=$(run_env -e "RAILWAY_PUBLIC_DOMAIN=relay.example.app" \
  | grep -oE '^RELAY_OPERATOR_API_ORIGIN=.*' | cut -d= -f2)
if [[ "$origin" == "https://relay.example.app" ]]; then
  pass "derives the operator API origin from the public domain"
else
  fail "derives the operator API origin from the public domain" \
       "https://relay.example.app" "${origin:-<unset>}"
fi

# 10. An explicit operator allowlist must win — the deployer may want operators
#     who are not the owner.
opk="2222222222222222222222222222222222222222222222222222222222222222"
kept_op=$(run_env -e "RELAY_OPERATOR_PUBKEYS=$opk" | grep -oE '^RELAY_OPERATOR_PUBKEYS=.*' | cut -d= -f2)
if [[ "$kept_op" == "$opk" ]]; then
  pass "leaves an explicit operator allowlist alone"
else
  fail "leaves an explicit operator allowlist alone" "$opk" "${kept_op:-<unset>}"
fi

# 11. The desktop app only accepts bech32 nsec1 keys, so a banner printing raw
#     hex walls every deployer at first login. Checked against known-good
#     vectors because a subtly wrong bech32 encoder is worse than none.
nsec_out=$(docker run --rm --entrypoint buzz-nsec "$IMG" \
  nsec fa20c1ddcd070e332a2d3fb28e72196bcd1236fbe1262ff152c6ab77ed179c9e 2>&1)
npub_out=$(docker run --rm --entrypoint buzz-nsec "$IMG" \
  npub 8bc0b8a4ffaf6916f24fc7d35201e9fb33b26912cfc8426c2ec4e764aa312828 2>&1)
want_nsec="nsec1lgsvrhwdqu8rx23d87eguused0x3ydhmuynzlu2jc64h0mghnj0qe4dsj3"
want_npub="npub130qt3f8l4a53duj0clf4yq0flvemy6gjelyyympwcnnkf2339q5q5nqxk9"
if [[ "$nsec_out" == "$want_nsec" && "$npub_out" == "$want_npub" ]]; then
  pass "encodes bech32 nsec/npub matching known vectors"
else
  fail "encodes bech32 nsec/npub matching known vectors" \
       "$want_nsec / $want_npub" "$nsec_out / $npub_out"
fi

# 12. The generated-key banner must carry the nsec, since that is the only form
#     the desktop app will accept.
banner=$(docker run --rm --tmpfs /data/git:uid=0,gid=0,mode=0755 "$IMG" true 2>&1)
if [[ "$banner" == *"nsec1"* ]]; then
  pass "prints an nsec in the generated-key banner"
else
  fail "prints an nsec in the generated-key banner" "banner containing nsec1…" \
       "$(echo "$banner" | head -12)"
fi

# 14. The community-creation helper must produce a valid signed request: a
#     kind-27235 event whose signed URL is the public origin (not the socket),
#     so a deployer can list extra workspaces and the relay accepts them.
auth=$(docker run --rm -e BUZZ_PROVISION_PRINT_AUTH=1 --entrypoint buzz-provision "$IMG" \
  fa20c1ddcd070e332a2d3fb28e72196bcd1236fbe1262ff152c6ab77ed179c9e \
  https://relay.example.app team2.relay.example.app \
  8bc0b8a4ffaf6916f24fc7d35201e9fb33b26912cfc8426c2ec4e764aa312828 3000 2>&1)
decoded=$(printf '%s' "$auth" | base64 -d 2>/dev/null)
if [[ "$decoded" == *'"kind":27235'* \
   && "$decoded" == *'https://relay.example.app/operator/communities'* \
   && "$decoded" == *'"method"'*'"POST"'* ]]; then
  pass "signs a valid community-creation request against the public origin"
else
  fail "signs a valid community-creation request against the public origin" \
       "kind 27235 event signing the public-origin operator URL" \
       "${decoded:0:200}"
fi

# 15. The desktop and mobile apps run from a non-web origin (tauri://localhost),
#     so a relay whose allowed origins are locked to the public web address
#     silently blocks every app read — the request never even leaves the app.
#     Whenever origins are restricted, the app origins must be added, or nobody
#     can connect with the app.
cors=$(run_env -e "BUZZ_CORS_ORIGINS=https://relay.example.app" \
  | grep -oE '^BUZZ_CORS_ORIGINS=.*' | cut -d= -f2)
if [[ "$cors" == *"https://relay.example.app"* && "$cors" == *"tauri://localhost"* ]]; then
  pass "keeps the app origins allowed even when origins are restricted"
else
  fail "keeps the app origins allowed even when origins are restricted" \
       "the site origin plus tauri://localhost" "${cors:-<unset>}"
fi

echo
if [[ $FAILED -eq 0 ]]; then
  echo "boot_test: PASS"
else
  echo "boot_test: FAIL"
fi
exit $FAILED
