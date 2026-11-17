#!/usr/bin/env bash
# End-to-end check of a live deploy through upstream buzz-cli, the client
# agents use. Covers what a healthcheck can't: the owner can create a channel,
# post and read back, upload media (MinIO), and a stranger is kept out until
# they redeem the invite link the relay prints at boot.
#
# Usage:
#   BUZZ_URL=https://<buzz domain> OWNER_KEY=<nsec from deploy logs> \
#   INVITE_CODE=<code from the boot link> BUZZ_CLI="<buzz-cli command>" \
#   ./test/e2e.sh
#
# BUZZ_CLI runs `buzz` from block/buzz crates/buzz-cli at the relay's release
# tag. It must pass BUZZ_PRIVATE_KEY and BUZZ_RELAY_URL through, and read files
# from $WORK. Needs uv (for test/nip98.py) and curl.
set -uo pipefail

: "${BUZZ_URL:?}" "${OWNER_KEY:?}" "${INVITE_CODE:?}" "${BUZZ_CLI:?}"
WORK="${WORK:-$(mktemp -d)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=(uv run -q --python 3.12 --with coincurve --with requests python3 -I "$HERE/nip98.py")
export BUZZ_RELAY_URL="$BUZZ_URL"
FAILED=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; FAILED=1; }
as() { local key=$1; shift; BUZZ_PRIVATE_KEY="$key" $BUZZ_CLI "$@"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

echo "e2e: $BUZZ_URL"
ts=$(date +%s)

# 1. Owner creates an open channel.
out=$(as "$OWNER_KEY" channels create --name "e2e-$ts" --type stream --visibility open 2>&1)
chan=$(jget 'd.get("channel_id") or d.get("id") or d["channel"]["id"]' <<<"$out" 2>/dev/null)
[[ "$chan" =~ ^[0-9a-f-]{36}$ ]] && ok "owner creates channel ($chan)" || bad "owner creates channel" "$out"

# 2. Owner posts with an attachment, which goes through Blossom into MinIO.
printf 'buzz e2e %s\n' "$ts" > "$WORK/e2e-$ts.txt"
out=$(as "$OWNER_KEY" messages send --channel "$chan" --content "hello from e2e $ts" --file "e2e-$ts.txt" 2>&1)
[[ $? -eq 0 ]] && ok "owner posts with an attachment" || bad "owner posts with an attachment" "$out"

# 3. Read back: the message and its media URL, and the media bytes.
out=$(as "$OWNER_KEY" messages get --channel "$chan" --limit 5 2>&1)
[[ "$out" == *"hello from e2e $ts"* ]] && ok "owner reads the message back" || bad "owner reads the message back" "$out"
url=$(grep -oE 'https://[^"<> )]+/media/[0-9a-f]{64}[^"<> )]*' <<<"$out" | head -1)
if [[ -n "$url" ]]; then
  got=$(cd "$WORK" && as "$OWNER_KEY" media get "$url" --output "dl-$ts" >/dev/null 2>&1; cat "$WORK/dl-$ts" 2>/dev/null)
  [[ "$got" == "buzz e2e $ts" ]] && ok "media downloads intact from MinIO" || bad "media downloads intact from MinIO" "url=$url got=${got:0:80}"
else
  bad "message carries a media URL" "${out:0:300}"
fi

# 4. A stranger is refused, redeems the invite, then can read and post.
stranger=$("${PY[@]}" genkey)
[[ "$stranger" =~ ^[0-9a-f]{64}$ ]] || { bad "make a stranger key" "$stranger"; stranger=none; }
out=$(as "$stranger" channels list 2>&1); rc=$?
[[ $rc -ne 0 ]] && ok "stranger is refused before joining (exit $rc)" || bad "stranger is refused before joining" "$out"
out=$(KEY="$stranger" "${PY[@]}" claim "$BUZZ_URL" "$INVITE_CODE" 2>&1)
[[ $? -eq 0 ]] && ok "stranger redeems the invite" || bad "stranger redeems the invite" "$out"
as "$stranger" channels join --channel "$chan" >/dev/null 2>&1
out=$(as "$stranger" messages send --channel "$chan" --content "stranger says hi $ts" 2>&1)
[[ $? -eq 0 ]] && ok "invited member posts" || bad "invited member posts" "$out"
out=$(as "$OWNER_KEY" messages get --channel "$chan" --limit 5 2>&1)
[[ "$out" == *"stranger says hi $ts"* ]] && ok "owner sees the member's message" || bad "owner sees the member's message" "${out:0:300}"

echo
[[ $FAILED -eq 0 ]] && echo "e2e: PASS" || echo "e2e: FAIL"
exit $FAILED
