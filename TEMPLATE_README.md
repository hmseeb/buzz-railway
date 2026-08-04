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

Buzz needs five coordinated services and persistent storage for three of them,
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
- **Pairing** — a small stateless helper the desktop app uses to link the Buzz
  mobile app by QR code.

All four are included in this template and wired up automatically.

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
2. Right after you make your identity, the app asks you to join a community. On
   that screen, click **Copy your public ID** (see the picture below). That is
   your public key, starting with `npub`, and it is safe to share. Do not use
   the key shown on the create-identity screen, that one is private.
3. When you deploy, paste that `npub` into the **RELAY_OWNER_PUBKEY** field.
   That makes you the owner.
4. When the deploy finishes, open the Buzz service's address from Railway in a
   browser (looks like `buzz-production-xxxx.up.railway.app`). You will see the
   empty-community page below. Click **Open in Buzz** — the app opens and
   connects you as the owner, with nothing to type. If nothing happens, the app
   is not installed yet; you can also add the community by hand in the app using
   `wss://` plus that same address.

**Which button to click, exactly:**

![The Copy your public ID button on the Buzz join screen](https://hmseeb.github.io/buzz-railway/copy-public-id.png)

**And after it deploys, at your server's address:**

![The empty-community page, with an Open in Buzz button](https://hmseeb.github.io/buzz-railway/open-in-buzz.png)

Full walkthrough with pictures: [hmseeb.github.io/buzz-railway](https://hmseeb.github.io/buzz-railway#setup)

There is no password reset, so back up your key from the app (Settings) and
keep it somewhere safe.

**Prefer not to set up the app first?** Type the word `generate` in the
`RELAY_OWNER_PUBKEY` field and a key is made for you. The Buzz service's logs
print it once as a `secret (sign in with this): nsec1…` line. Copy it, open the
app, choose **Use an existing key**, paste it, then connect to your server
address as above.

**The workspace is private.** Invite teammates with links you create from
inside the app.

**More than one workspace on the same server:** list extra hostnames in the
`BUZZ_EXTRA_COMMUNITY_HOSTS` variable (comma-separated) and point those domains
at the Buzz service. Each is created automatically on the next restart, up to
three per owner.

**Deployed before August 2026 and mobile pairing fails?** Pairing the mobile
app needs a small helper service that older deploys don't have — template
updates don't reach projects that are already deployed, so add it once by hand:

1. In your project, add a new service from the Docker image
   `ghcr.io/hmseeb/buzz-railway:latest`, set its start command to
   `buzz-pair-relay`, add a variable `BUZZ_PAIR_RELAY_BIND_ADDR` set to
   `0.0.0.0:5000`, and generate a public domain for it targeting port 5000.
2. On the Buzz service, add a variable `BUZZ_PAIRING_RELAY_URL` set to `wss://`
   plus the domain from step 1. Saving restarts the server for a few seconds.

That's it — the desktop app finds the helper on its own afterwards. Deploys
made after August 2026 include it already.

Buzz is built by [Block, Inc.](https://github.com/block/buzz) and licensed
Apache-2.0. This template only packages it for Railway.
