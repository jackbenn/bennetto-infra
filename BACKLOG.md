# Backlog — bennetto-infra

Prefix: INFRA · Next ID: 8 · Schema: v1

## [INFRA-1] Stop every deploy from recreating every container

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** deploy, bug

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
- [ ] A deploy with no changes recreates nothing

## [INFRA-2] Rebuild gengo-ws only when the game server's code changes

- **Status:** idea
- **Priority:** unknown
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
- **Priority:** unknown
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
- **Priority:** unknown
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

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** docker, server

The server's shell history shows `docker system prune -a` run several times,
presumably to free disk: the root volume is 11 GB and was 75% full on
2026-10-25. That deletes the whole build cache, so the next deploy rebuilds every
image from scratch (the Oct 25 deploy rebuilt even bookclub's `apt-get` layer)
and, with INFRA-1, would recreate every container regardless.

**What to do:** grow the EBS volume, or replace the manual prune with something
that keeps recent cache, for example a weekly cron running `docker builder
prune --filter until=168h` and `docker image prune`. Note the choice in
`DEPLOY.md` and `setup-server.sh`.

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
