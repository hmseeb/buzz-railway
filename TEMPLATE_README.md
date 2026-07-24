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

You reach it with the **Buzz desktop or mobile app**, not a browser. After the
deploy finishes, the relay prints an owner key once into its deploy logs; you
paste that into the app and you're in as administrator. Because the relay
resolves communities by hostname, one deployment can host several separate
workspaces — a second workspace is a DNS record, not a second bill.

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

1. Wait about a minute for all four services to go green.
2. Install the Buzz app (once) from the
   [releases page](https://github.com/block/buzz/releases/latest) — macOS
   `.dmg`, Windows `.exe`, Linux `.AppImage`/`.deb`.
3. Open the **Buzz** service's deploy logs. On first boot it prints a one-click
   connect link:

   ```
   buzz-boot: Your workspace is ready. Open it in the Buzz app with one
   buzz-boot: click — no keys to paste:
   buzz-boot:   https://<your-service>.up.railway.app/invite/…
   ```

4. Click that link. Your browser shows an **Open in Buzz** button — click it,
   and the app opens already connected to your workspace. You're the owner.

**Back up your key.** Just above the link the logs print a
`secret (sign in with this): nsec1…` line — save it in a password manager.
That is your permanent sign-in; there is no password reset, and clearing the
app without it locks you out. A copy is also kept on the server's volume. If
you would rather use a Nostr identity you already own, set `RELAY_OWNER_PUBKEY`
to its 64-character hex public key before the first deploy and no key is
generated (in that case connect manually: choose **Use an existing key**, paste
your key, and point the app at `wss://<your-service>.up.railway.app`).

**The workspace is private.** Invite teammates with links you create from
inside the app.

**More than one workspace on the same server:** list extra hostnames in the
`BUZZ_EXTRA_COMMUNITY_HOSTS` variable (comma-separated) and point those domains
at the Buzz service. Each is created automatically on the next restart — up to
three per owner.

Buzz is built by [Block, Inc.](https://github.com/block/buzz) and licensed
Apache-2.0. This template only packages it for Railway.
