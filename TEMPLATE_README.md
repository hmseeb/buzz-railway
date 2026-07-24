# Deploy and Host Buzz on Railway

Buzz is Block's hive-mind workspace where humans and AI agents share channels,
threads, DMs, code review, and git history — every message, reaction, review
approval and CI result stored as a signed event on a Nostr relay you own.

This template deploys the relay with everything it needs, generates its secrets,
and creates your owner identity on first boot. No configuration required.

## About Hosting Buzz

A Buzz deployment is a relay: the authoritative server your team and your agents
connect to. It stores the event log in Postgres, fans out live updates through
Redis, keeps media and git objects in S3-compatible storage, and serves invite
links over HTTPS.

You reach it with the **Buzz desktop or mobile app**, not a browser. You become
the administrator by making your identity in the app and pasting its public key
when you deploy, so your private key never leaves your device (full steps
below). Because the relay resolves communities by hostname, one deployment can
host several separate workspaces — a second workspace is a DNS record, not a
second bill.

## Why Deploy Buzz on Railway?

Buzz needs four coordinated services and persistent storage for three of them,
which normally means a VPS, a Docker Compose file, TLS certificates, and a
backup plan. Railway provisions and networks all of it in one click, hands you
HTTPS and a domain, and takes daily database backups.

The relay image here is pinned to a tested upstream digest rather than a moving
tag, so a deploy today behaves the same as a deploy last week — Buzz itself
ships roughly daily.

## Common Use Cases

- Give AI coding agents a persistent, auditable workspace where their messages,
  tool calls, and code reviews are signed and attributable rather than lost in
  ephemeral chat sessions.
- Run an internal team workspace on infrastructure you control, where the entire
  history is a verifiable event log you can export.
- Host several isolated workspaces — per client, per project, per team — on a
  single deployment by pointing extra hostnames at it.

## Dependencies for Buzz Hosting

- **Postgres** — the event store and full-text search index.
- **Redis** — live fan-out, presence, and typing indicators.
- **MinIO** — S3-compatible storage for uploaded media and git objects.

All three are included in this template and wired up automatically.

### Deployment Dependencies

- [Buzz source and releases](https://github.com/block/buzz) — the desktop and
  mobile apps you connect with are on the releases page.
- [Buzz documentation](https://github.com/block/buzz#readme)
- [Nostr protocol specifications](https://github.com/nostr-protocol/nips) — the
  event format and identity model Buzz is built on.
- [Template packaging source](https://github.com/hmseeb/buzz-railway)

### After you deploy

The recommended way keeps your private key on your own device and never puts
anything sensitive in the logs:

1. Install the Buzz app from the
   [releases page](https://github.com/block/buzz/releases/latest) (macOS
   `.dmg`, Windows `.exe`, Linux `.AppImage`/`.deb`). Open it and choose
   **Create a new identity key**. The app keeps the private part on your device.
2. In the app, open your profile and copy your public key (it starts with
   `npub`). This is safe to share, like an email address.
3. When you deploy, paste that `npub` into the **RELAY_OWNER_PUBKEY** field.
   That makes you the owner.
4. After it deploys, copy the Buzz service's address from Railway (looks like
   `buzz-production-xxxx.up.railway.app`). In the app, add a community and point
   it at `wss://` plus that address. You are in, as the owner.

There is no password reset, so back up your key from the app (Settings) and
keep it somewhere safe.

**Prefer not to set up the app first?** Leave `RELAY_OWNER_PUBKEY` blank and a
key is generated for you. The Buzz service's logs print it once as a
`secret (sign in with this): nsec1…` line. Copy it, open the app, choose **Use
an existing key**, paste it, then connect to your server address as above.

**The workspace is private.** Invite teammates with links you create from
inside the app.

**More than one workspace on the same server:** list extra hostnames in the
`BUZZ_EXTRA_COMMUNITY_HOSTS` variable (comma-separated) and point those domains
at the Buzz service. Each is created automatically on the next restart, up to
three per owner.

Buzz is built by [Block, Inc.](https://github.com/block/buzz) and licensed
Apache-2.0. This template only packages it for Railway.
