# Backlog — bennetto-infra

Prefix: INFRA · Next ID: 9 · Schema: v1

## [INFRA-1] Stop every deploy from recreating every container

- **Status:** active
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
- [ ] A deploy that changes only one site recreates only that site's containers (check the `Recreate` lines in `/tmp/deploy.log`)
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

## [INFRA-2] Rebuild gengo-ws only when the game server's code changes

- **Status:** idea
- **Priority:** P3
- **Size:** quick
- **Depends on:** INFRA-1
- **Tags:** deploy, docker
- **Related:** GENGO-3

`docker/gengo-ws.Dockerfile` copies the whole `gengo/` folder, so a change to a
template, the CSS or the Brython client scripts rebuilds the game server image
and restarts it, ending games, though the game server never uses those files.

**What to do:** copy only what `start_server.py` imports: `start_server.py`,
`gengo/__init__.py`, `gengo/server/` and `gengo/src/`. Then front-end changes
restart only `gengo-web`.

### Acceptance criteria
- [ ] A deploy that changes only files under `gengo/app/` leaves `gengo-ws` running (not recreated)

## [INFRA-3] Don't restart a service that is in use without asking

- **Status:** idea
- **Priority:** P3
- **Size:** session
- **Depends on:** INFRA-1
- **Tags:** deploy
- **Related:** GENGO-2, GENGO-3

Brief downtime is fine for these sites, but restarting `gengo-ws` mid-game
throws away the game. The deploy should find out what it is about to restart and
check whether any of it is busy first.

**What to do:** before the real `up`, run `docker compose up -d --build
--dry-run` on the server to list the containers it would recreate. For each, if
the service declares a busy check (say a compose label such as
`bennetto.busy-check` naming a command to `docker compose exec`), run it. If a
service is busy, bring up everything else, then report it and wait or ask
before restarting that one. Sites opt in with one label, so new sites need no
change to `deploy.sh`. For gengo the check would ask the game server whether any
game has two connected players. That needs a small addition to
`gengo/server/server.py`, which GENGO-2's connection tracking would make
straightforward.

Depends on INFRA-1, because until then the dry run lists every container.

### Acceptance criteria
- [ ] Deploying while a gengo game is in progress does not restart `gengo-ws` without saying so
- [ ] Services with no busy check deploy exactly as now

## [INFRA-4] gengo-ws prints nothing to `docker compose logs`

- **Status:** idea
- **Priority:** P3
- **Size:** quick
- **Depends on:** none
- **Tags:** logging, docker

While diagnosing the "Loading…" outages, `docker compose logs gengo-ws` was
empty, though the server `print`s each action it receives. Python fully
buffers stdout when it is not a terminal, so the output never reaches Docker.
Its `logging` calls are at INFO, below the default WARNING level, so they are
dropped too.

**What to do:** set `ENV PYTHONUNBUFFERED=1` in `docker/gengo-ws.Dockerfile`
(and in `gengo-web`'s for consistency), and consider configuring logging at INFO
in `start_server.py`.

### Acceptance criteria
- [ ] Opening `/gengo/` produces a line in `docker compose logs gengo-ws`

## [INFRA-5] Keep the server's Docker build cache

- **Status:** active
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** docker, server
- **Related:** INFRA-1, INFRA-8

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
`docker builder prune` capped at about 1 GB, plus `docker image prune -f`. The
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
- [ ] After a deploy, `docker buildx du` reports at most about 1 GB of build cache
- [ ] A deploy straight after a pruning deploy, with no changes, still recreates nothing and rebuilds nothing (every step `CACHED` in `/tmp/deploy.log`)

## [INFRA-6] Remove the open port 5000 from the EC2 security group

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** security, server

The instance's security group (`launch-wizard-19`, `sg-0eea6124015052947`) still
allows inbound TCP 5000 from anywhere (rule `sgr-0c815ae459449a286`). Nothing
listens there: `gengo-web` is only `expose`d to nginx. It is left over from
running Flask directly. Port 8765 was closed on 2026-10-25 (commit `5758fb0`
and the security group rule removed).

**What to do:** revoke the rule, and check that nothing else in the group is
unused.

### Acceptance criteria
- [ ] The security group allows inbound only 22, 80 and 443

## [INFRA-7] Fill in the README's Getting started

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** docs, baseline
- **Related:** META-6

project-init (2026-10-27) wrote a skeleton `README.md` with TODOs. Fill it in
with META-6's `repo-docs` skill: the submodule layout (one checkout of each
site, under this repo), local runs with `docker-compose.local.yml`, deploying
through the `publish-site` skill and `scripts/deploy.sh`, and what is not in
the repo (the EC2 server, certificates, secrets). Point at `DEPLOY.md` rather
than repeating it.

## [INFRA-8] Cap the systemd journal on the server

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** logging, server
- **Related:** INFRA-5

On 2026-11-01 `/var/log/journal` was 456 MB of the 11 GB root volume (79%
full). `journald.conf` sets no limit, so the default applies: 10% of the
filesystem, about 1.1 GB here, so it can still roughly double.

**What to do:** add a drop-in such as `/etc/systemd/journald.conf.d/size.conf`
with `SystemMaxUse=` set to something small (100–200 MB), restart
`systemd-journald`, and vacuum the existing journal down to it
(`journalctl --vacuum-size=`). Write the drop-in from `setup-server.sh` so a
rebuilt server gets it too, and mention it in `DEPLOY.md`.

### Acceptance criteria
- [ ] `journalctl --disk-usage` reports no more than the cap
- [ ] `setup-server.sh` writes the drop-in
