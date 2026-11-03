# Backlog — bennetto-infra

Prefix: INFRA · Next ID: 11 · Schema: v1

## [INFRA-2] Rebuild gengo-ws only when the game server's code changes

- **Status:** idea
- **Priority:** P3
- **Size:** quick
- **Depends on:** INFRA-1
- **Tags:** deploy, docker
- **Related:** GENGO-3, INFRA-5

`docker/gengo-ws.Dockerfile` copies the whole `gengo/` folder, so a change to a
template, the CSS or the Brython client scripts rebuilds the game server image
and restarts it, ending games, though the game server never uses those files.

**What to do:** copy only what `start_server.py` imports: `start_server.py`,
`gengo/__init__.py`, `gengo/server/` and `gengo/src/`. Then front-end changes
restart only `gengo-web`.

While rewriting the Dockerfile, consider having `gengo-web` and `gengo-ws` share
their `pip install` layer through a common build stage. Each now installs
nearly the same requirements on its own, about 110 MB apiece in the image and
in the build cache (measured 2026-11-01, see INFRA-5).

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

## [INFRA-6] Remove the open port 5000 from the EC2 security group

- **Status:** done
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
- [x] The security group allows inbound only 22, 80 and 443

### Notes
- 2026-11-03: nothing listened on 5000 and the group is attached only to
  `i-02521ba84717051f6`, so Jack revoked `sgr-0c815ae459449a286`. Inbound is
  now 22 (IPv4), 80 and 443 (IPv4 and IPv6); the other rules are all in use.
  Port 5000 now times out from outside; the sites and SSH still answer.

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

## [INFRA-9] Pin the Python base image

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** docker, server
- **Related:** INFRA-5

All four built images start `FROM python:3.11-slim`, a tag Docker Hub moves
every week or two. Each time a deploy pulls a new version, every `pip install`
layer on top is invalidated and rebuilt, which restarts every site, and the old
base and its layers linger in the build cache: on 2026-11-01 the cache held
three versions of the base, about 525 MB of it stale.

**What to do:** pin by digest (`FROM python:3.11-slim@sha256:…`) in
`docker/gengo-web.Dockerfile`, `docker/gengo-ws.Dockerfile`,
`docker/taking-the-story.Dockerfile` and `bookclub/Dockerfile` (a submodule, so
a bookclub commit), all to the same digest so they share the layers. Updating
the base then becomes a deliberate step, done for security fixes; note in
`DEPLOY.md` how and how often, and perhaps a small script that bumps all four.

### Acceptance criteria
- [ ] All four Dockerfiles use the same pinned digest
- [ ] `DEPLOY.md` says how to update the base image

## [INFRA-10] Script to create and check the EC2 security group

- **Status:** idea
- **Priority:** unknown
- **Size:** quick
- **Depends on:** none
- **Tags:** security, server
- **Related:** INFRA-6

The security group's rules live only in AWS and in the table in `DEPLOY.md`
("Firewall (EC2 security group)"). Moving to another region or VPC means
recreating them by hand, and nothing notices a stray rule: port 5000 stayed
open for months after Flask stopped serving it directly (INFRA-6).

**What to do:** add `scripts/security-group.sh`, using the AWS CLI. With no
arguments it creates a properly named group (say `bennetto-web`) in a given
VPC with exactly the rules in `DEPLOY.md`. With `--check <group-id>` it lists
any rule missing from, or extra to, that list and exits non-zero if there are
any. Keep the rule list in one place in the script, and point `DEPLOY.md`'s
table at it (or generate the table from it).

### Acceptance criteria
- [ ] `scripts/security-group.sh --check sg-0eea6124015052947` reports no differences
- [ ] Creating a group with the script in a scratch VPC gives exactly the rules in `DEPLOY.md`
