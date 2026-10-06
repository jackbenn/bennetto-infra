# Deploy notes

(Uncommitted scratch file — not tracked by git, just here so this doesn't
have to be re-derived each time.)

## Making a change to any submodule (bookclub, gengo, taking_the_story, website) live

1. In the submodule's own repo, commit and push your change to its GitHub
   remote (normal `git commit` / `git push`, same as any other repo).

2. From `bennetto-infra`, run `scripts/deploy.sh`.

   You do **not** need to manually bump the submodule pointer first — the
   script does it for you:
   - Fetches every submodule's remote.
   - For each submodule that's ahead/behind its own origin, pushes or
     fast-forward pulls it as needed.
   - Commits the resulting pointer update(s) in `bennetto-infra` (message:
     "update submodule pointers: <names>").
   - Pushes `bennetto-infra` to GitHub.
   - SSHes to the `website` host, runs `git pull --recurse-submodules`,
     then kicks off `docker compose up -d --build` detached (survives
     SSH disconnect). Build output goes to `/tmp/deploy.log` on the server.

3. Watch the build: `ssh website tail -f /tmp/deploy.log`

The script bails early if any submodule has a merge conflict, or has
diverged from its own origin (ahead *and* behind) — resolve those by hand
first (`cd <submodule> && git pull` / merge, then push).

No separate migration step is needed for schema changes — each
container's Dockerfile CMD runs `alembic upgrade head` before starting
the server, so migrations run automatically on every deploy.

## If a submodule's local checkout looks stale / diverged

Check with:
```
cd bennetto-infra
git submodule status
```
A `+` prefix means the checked-out commit differs from what
`bennetto-infra` has recorded — normal right after you push a submodule
change yourself, and `deploy.sh` will pick it up. If it's unexpected
(you didn't just push anything), check `git -C <submodule> log` for
commits made directly in that submodule's clone that never got pushed to
its GitHub remote, or vice versa (pushed there but never pulled back
locally) — reconcile with a normal `git pull`/merge in that submodule
before deploying.
