# Backlog archive — bennetto-infra

Prefix: INFRA · Archive of: BACKLOG.md · Schema: v1

## [INFRA-1] Stop every deploy from recreating every container

- **Status:** done
- **Priority:** P3
- **Size:** quick
- **Depends on:** none
- **Tags:** deploy, bug
- **Commits:** 40e95da

`deploy.sh` runs `docker compose up -d --build`, and on the server every built
service gets a new image ID on every build, even when every layer is cached. The
cause is the provenance attestation BuildKit adds by default, which is
regenerated each build. Compose then recreates every container, restarting all
the sites, and in particular ending every gengo game in progress.

Verified 2026-10-25 on the server: two back-to-back `docker compose build
bookclub` runs with nothing changed gave different image IDs; with
`BUILDX_NO_DEFAULT_ATTESTATIONS=1` exported they gave the same ID. Both deploys
that day recreated bookclub and taking-the-story though neither had changed.

**What to do:** export `BUILDX_NO_DEFAULT_ATTESTATIONS=1` for the remote
`docker compose up` in `scripts/deploy.sh` (or set the equivalent in the compose
file, if Compose supports it for these builds). Docker's own cache then decides
what restarts, which keeps working as sites are added, with no
submodule-to-service map to maintain. Update `DEPLOY.md` to say only changed
services restart.

### Acceptance criteria
- [x] A deploy that changes only one site recreates only that site's containers (check the `Recreate` lines in `/tmp/deploy.log`)
- [x] A deploy with no changes recreates nothing

### Notes
- 2026-11-01: tried the compose-file route first, so manual `docker compose up`
  runs would be covered too. On the server (Compose v5.1.1, buildx v0.31.1,
  containerd snapshotter), `build: provenance: false` and `provenance: false` +
  `sbom: false` both still gave a new bookclub image ID every build;
  `BUILDX_NO_DEFAULT_ATTESTATIONS=1` gave the same ID three times. So the
  variable is exported in `scripts/deploy.sh`, and `DEPLOY.md`'s manual
  command now includes it.
- 2026-11-01: the first deploy after this still recreates every service, since
  the earlier images were built with attestations.
- 2026-11-01: deployed 40e95da with the gengo and taking_the_story pointers
  (bc0b103); as expected it recreated all four built services. An immediate
  second deploy with no changes recreated nothing: every container `Running`.
  The single-site criterion is still to check, on the next real deploy that
  changes one site.
- 2026-11-01: Verified on the deploy of 1a60dcd, which changed only gengo
  (GENGO-8): `/tmp/deploy.log` shows `Recreate` for `gengo-web` and
  `gengo-ws` only; `bookclub`, `taking-the-story` and `nginx` stayed
  `Running`, with their creation times unchanged. Also seen at 00:00 UTC that
  day: `gengo-web` alone was rebuilt and recreated with no gengo change, most
  likely because INFRA-5's first cache trim (1 GB) evicted its layers and the
  rebuild re-ran an unpinned `pip install` (gengo's `requirements.txt` pins
  nothing). Not confirmed. INFRA-9 pins the base image but not the packages.

## [INFRA-5] Keep the server's Docker build cache

- **Status:** done
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** docker, server
- **Related:** INFRA-1, INFRA-8, INFRA-9
- **Commits:** 111104d, 043f061

The server's shell history shows `docker system prune -a` run several times,
presumably to free disk: the root volume is 11 GB and was 75% full on
2026-10-25. That deletes the whole build cache, so the next deploy rebuilds every
image from scratch (the Oct 25 deploy rebuilt even bookclub's `apt-get` layer)
and recreates every container, undoing INFRA-1.

The instance is a t3.micro and Jack doesn't want to keep much, so the fix is to
bound the cache rather than grow the volume. On 2026-11-01 the disk was 79%
full (2.3 GB free). Docker took about 4.5 GB: the five current images about
1.3 GB and the build cache 3.2 GB. Only 0.70 GB of that cache had been used
by that day's builds; the rest was 0.68 GB last used a week before, 1.27 GB three
to five weeks before and 0.53 GB two months before, mostly superseded `pip
install` layers.

**What to do:** at the end of the remote build in `scripts/deploy.sh`, run
`docker builder prune` capped at about 2 GB, plus `docker image prune -f`. The
cache only grows on a build, so pruning right after one needs no cron job. Cap
by size, which evicts least recently used entries, rather than by age (`--filter
until=168h`), which would keep a busy week's cache regardless of size and drop
an untouched site's cache even when there is room. Not BuildKit's GC in
`/etc/docker/daemon.json`: enabling it restarts the daemon and every container.

Before writing it, check on the server (`docker builder prune --help`) which flag
means "prune least recently used until under N": Docker has been replacing
`--keep-storage` with `--max-used-space` and `--reserved-space`, which mean
different things. Note the policy in `DEPLOY.md`, with a warning not to run
`docker system prune -a` by hand.

### Acceptance criteria
- [x] After a deploy, `docker buildx du` reports at most about 2 GB of build cache
- [x] A deploy straight after a pruning deploy, with no changes, still recreates nothing and rebuilds nothing (every step `CACHED` in `/tmp/deploy.log`)

### Notes
- 2026-11-01: deployed 111104d. The prune removed 2.1 GB, leaving 1.07 GB
  (`1GB` is read as 1 GiB); root volume went from 76% to 58% full and nothing
  restarted. But the next no-change deploy rebuilt gengo-web's `pip install`
  layer and recreated gengo-web: the cap had evicted a layer a current image
  needs. The measure that suggested 1 GB (0.70 GB used that day) undercounted;
  the cache after that rebuild was 1.22 GB. The cap needs raising, with room to
  spare.
- 2026-11-01: of that 1.22 GB, about 620 MB is what current images need (430 MB
  of `pip install` layers, 190 MB of `python:3.11-slim`); about 525 MB is two
  older base-image versions and library layers built on them. The prune kept
  some 3-week-old entries while evicting a needed one, so BuildKit's
  last-used order is not fully reliable. Raised the cap to 2 GB: room for
  what is needed plus about one stale generation. Shrinking the cache itself is
  INFRA-9 (pin the base) and INFRA-2 (shared gengo layer).
- 2026-11-01: deployed 043f061. Every `RUN`/`COPY` step `CACHED`, nothing
  recreated, cache 1.22 GB with nothing pruned; root volume 59% full. Caveat:
  this run was under the cap, so it does not show that a real prune at 2 GB
  keeps every needed layer. That will first be tested when the cache next
  passes 2 GB, most likely after a base-image update (INFRA-9). If a
  no-change deploy then rebuilds something, reopen this.

## [INFRA-8] Cap the systemd journal on the server

- **Status:** done
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** logging, server
- **Related:** INFRA-5
- **Commits:** 4b584a5

On 2026-11-01 `/var/log/journal` was 456 MB of the 11 GB root volume (79%
full). `journald.conf` sets no limit, so the default applies: 10% of the
filesystem, about 1.1 GB here, so it can still roughly double.

**What to do:** add a drop-in such as `/etc/systemd/journald.conf.d/size.conf`
with `SystemMaxUse=` set to something small (100–200 MB), restart
`systemd-journald`, and vacuum the existing journal down to it
(`journalctl --vacuum-size=`). Write the drop-in from `setup-server.sh` so a
rebuilt server gets it too, and mention it in `DEPLOY.md`.

### Acceptance criteria
- [x] `journalctl --disk-usage` reports no more than the cap
- [x] `setup-server.sh` writes the drop-in

### Notes
- 2026-11-01: capped at 150M (`/etc/systemd/journald.conf.d/size.conf`) and
  applied on the server. Restarting journald alone brought it from 456 MB to
  137 MB; root volume went from 79% to 76% full.
