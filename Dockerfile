# Thin wrapper over the upstream Buzz relay that resolves the relay owner at
# boot. Pinned by digest because upstream publishes no semver tags to GHCR —
# only :main, :latest and :sha-<7> — so a floating tag would ship whatever
# landed on main that morning to everyone who clicks Deploy.
#
# digest = ghcr.io/block/buzz:main as of 2026-07-24
FROM ghcr.io/block/buzz@sha256:380198f4106c733a1b91733be1053440ed229cca87ef0de581a787de3f43065a

# Without this the image inherits upstream's source label and GHCR attributes
# the package to block/buzz rather than to this repo.
LABEL org.opencontainers.image.title="Buzz for Railway" \
      org.opencontainers.image.description="Buzz relay packaged for one-click Railway deploys" \
      org.opencontainers.image.source="https://github.com/hmseeb/buzz-railway"

USER root

# Pre-create the git data dir owned by the relay user. Docker propagates this
# ownership onto a fresh named volume, which is where the owner key persists.
RUN mkdir -p /data/git && chown 1000:1000 /data/git

COPY --chmod=0755 buzz-boot /usr/local/bin/buzz-boot

# Deliberately stays root: the entrypoint needs to chown a root-owned mounted
# volume before it can hand off. It drops to uid 1000 via setpriv immediately
# after, so the relay itself never runs privileged.
ENTRYPOINT ["/usr/local/bin/buzz-boot"]
CMD ["buzz-relay"]
