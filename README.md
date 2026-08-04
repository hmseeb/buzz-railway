# Buzz on Railway

One-click deploy for [Buzz](https://github.com/block/buzz), Block's hive-mind
workspace where humans and AI agents share channels, code review, and git
events on a Nostr relay.

This repo holds two things: the Railway template definition, and a thin wrapper
image that makes a zero-input deploy actually work.

## What you get

The relay with its bundled web UI, a mobile-pairing helper, Postgres, Redis,
and MinIO for media. Five services, one URL, no configuration required.

## Why a wrapper image

Upstream's container is used as-is except for one boot step.

`buzz-relay` requires `RELAY_OWNER_PUBKEY` — 64 hex characters identifying the
relay's owner — and warn-and-ignores anything malformed, starting up regardless.
The result is a relay that runs, serves a UI, and cannot be administered by
anyone, with only a `WARN` line to explain it. Someone clicking Deploy is also
unlikely to have a Nostr keypair to hand.

So `buzz-boot` runs first and either:

- validates the pubkey you supplied, refusing to start if it isn't hex (an
  `npub` is bech32, and pasting one is the obvious mistake), or
- generates a keypair with `buzz-admin generate-key`, persists it to the data
  volume, and prints the secret key once in the deploy logs.

It then `exec`s the relay. The behaviour is pinned by
[`test/boot_test.sh`](test/boot_test.sh), which runs in CI before publish.

The same image also runs the Pairing service with `buzz-pair-relay` as the
command. Mobile pairing is served by that sidecar, not the relay — `buzz-boot`
hands off to it directly (no owner key, no volume) and rebinds it from
upstream's loopback default to `$PORT`, while `BUZZ_PAIRING_RELAY_URL` on the
relay advertises its address via NIP-11 so the desktop app finds it instead of
falling back to a `/pair` path nothing serves.

## Pinning

Upstream publishes no semver tags to GHCR — only `:main`, `:latest` and
`:sha-<7>` — and ships roughly daily. The wrapper pins upstream by digest so a
deploy is reproducible, and the digest moves when it is tested, not whenever
main does.

## Running the test

```bash
docker build -t buzz-railway:test .
./test/boot_test.sh
```

Needs Docker. Takes about a minute.

## Credits

Buzz is built by [Block, Inc.](https://github.com/block/buzz) and licensed
Apache-2.0. This repo only packages it for Railway.
