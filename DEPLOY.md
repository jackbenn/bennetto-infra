# Deploying bennetto.com

Everything on bennetto.com runs as one Docker Compose stack on a single EC2
host, built from this repo. Each site is a git submodule here, with one checkout
of each.

## What runs where

| Submodule | Compose service(s) | Served at | Build | Migrations | Before deploying |
|---|---|---|---|---|---|
| `website` | none, bind-mounted into `nginx` | `bennetto.com/` | none: static files, live as soon as the server pulls | none | none |
| `gengo` | `gengo-web`, `gengo-ws` | `bennetto.com/gengo/`, websocket on `:8765` | `docker/gengo-*.Dockerfile` | none | none |
| `taking_the_story` | `taking-the-story` | `bennetto.com/story/` | `docker/taking-the-story.Dockerfile` | none: SQLite in volume `taking_the_story_data`, schema created on startup | none |
| `bookclub` | `bookclub` | `bookclub.bennetto.com` | `bookclub/Dockerfile` | `alembic upgrade head` on every container start | run `pytest` if the repo has tests; any new env var must be added to `bookclub.env` on the server *before* deploying |

nginx routes requests by host and path (`nginx/conf.d/`). Secrets for bookclub
live in `bookclub.env` beside `docker-compose.yml` on the server. That file is
not in git, and `bookclub/infra/bookclub.env.example` lists the keys.

The deploy script reaches the server through an SSH alias named `website` in
`~/.ssh/config`:

```
Host website
  HostName <the EC2 instance; bennetto.com resolves to it>
  User ubuntu
  IdentityFile <the instance's key>
```

To run the whole stack locally over HTTP at `http://localhost:8080`:
`docker compose -f docker-compose.yml -f docker-compose.local.yml up`.

## Making a change to a site live

1. In the submodule, commit the change. Pushing it is optional, because the
   script pushes any submodule that is ahead of its origin.

2. From `bennetto-infra`, run `scripts/deploy.sh`.

   You do **not** need to bump the submodule pointer yourself. The script, in
   order:
   - Stops if any submodule has a merge conflict (`U` in `git submodule status`).
   - Warns about uncommitted changes in a submodule. Only commits get deployed.
   - Fetches every submodule's remote.
   - For each submodule: pushes it if it is ahead of origin, fast-forward pulls
     it if it is behind, and **stops** if it has diverged (ahead *and* behind).
   - Stages the pointer of every submodule whose checked-out commit differs from
     the one recorded here. That covers drift from a manual pull too, not just
     what it pushed or pulled itself.
   - Commits those pointers (`update submodule pointers: <names>`).
   - Pushes `bennetto-infra`.
   - SSHes to `website`, runs `git pull --recurse-submodules` in
     `~/bennetto-infra`, then starts `docker compose up -d --build` detached
     (`nohup`, so it survives the SSH session ending). Build output goes to
     `/tmp/deploy.log` on the server.

3. Watch the build: `ssh website tail -f /tmp/deploy.log`. It is done when
   compose reports each container `Started` or `Running`. Then check the site.

No separate migration step is needed. bookclub's Dockerfile CMD runs
`alembic upgrade head` before starting the server, so its migrations run on
every deploy. The other apps have no migrations.

## When the script stops

**A submodule has diverged from its origin.** Commits were made in this
checkout and different commits were pushed elsewhere. Reconcile in the
submodule, then deploy again:

```
cd <submodule>
git pull          # merge or rebase, resolve conflicts
git push
```

**A merge conflict in a submodule.** Finish or abort the merge in that
submodule first.

**`git push` of `bennetto-infra` is rejected.** Its origin has commits this
checkout lacks. The pointer commit is already made locally, so
`git pull --rebase` here and rerun the script.

**A submodule is on a detached HEAD.** `git submodule update` leaves submodules
detached, and then the ahead/behind check sees nothing to push or pull.
`git -C <submodule> switch main` before deploying.

## Reading `git submodule status`

```
cd bennetto-infra
git submodule status
```

The first character of each line:

- ` ` (space): the checkout matches the recorded pointer.
- `+`: the checked-out commit differs from what `bennetto-infra` has recorded.
  This is normal right after you commit in a submodule, and `deploy.sh` will
  record it. If you didn't just commit anything, check `git -C <submodule> log`
  for commits made in the submodule's clone that never reached its GitHub
  remote, or pushed there but never pulled back. Reconcile with a normal
  `git pull`/merge in that submodule before deploying.
- `-`: the submodule is not initialized. Run `git submodule update --init` and
  then switch it to `main`.
- `U`: a merge conflict.

## Rebuilding the server from scratch

On a fresh Ubuntu EC2 instance:

```
git clone --recurse-submodules https://github.com/jackbenn/bennetto-infra.git
cd bennetto-infra
bash scripts/setup-server.sh      # Docker, certbot, swap, renewal cron
```

Then log out and back in for the docker group to take effect, and:

1. `cp bookclub/infra/bookclub.env.example bookclub.env` and fill in the real
   secrets.
2. Point DNS for `bennetto.com`, `www.bennetto.com` and `bookclub.bennetto.com`
   at the instance, and update the `website` SSH alias on your machine.
3. Run `./scripts/deploy.sh` from your machine, or `docker compose up -d --build`
   on the server.
4. Once the sites answer on HTTP, run `bash scripts/issue-cert.sh` on the
   server. Renewal after that is the cron job that `setup-server.sh` installed.

   **Untested chicken-and-egg:** the prod nginx config listens on 443 with
   certificates under `/etc/letsencrypt/live/bennetto.com/`, so nginx probably
   won't start on a fresh host until those exist, and `issue-cert.sh` needs
   nginx serving the ACME challenge. Running `certbot certonly --standalone`
   with port 80 free, before the first `compose up`, is the likely way round.
   Verify that next time a server is built, and fix this note.

The SQLite databases live in the named volumes `taking_the_story_data` and
`bookclub_data`, and a new instance starts with them empty. To keep the data,
copy the volumes across before retiring the old instance.
