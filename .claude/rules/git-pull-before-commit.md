## Pull before committing locally after a PR merges via GitHub UI

When a PR is merged via the GitHub web UI (or `gh pr merge`), the resulting merge commit lands on `origin/dev` (or `origin/main`) but **not on your local `dev`**. If you then commit locally and push without pulling first, a `git push --force` / `--force-with-lease` will rewrite `origin/dev` backward to your local tip, silently clobbering the merge commit and any downstream work.

**Always** before committing on a local long-lived branch (`dev`, `main`):

```
git pull --ff-only origin dev
```

Use `--ff-only` deliberately — it refuses to merge / rebase if there's divergence, surfacing the problem at pull time instead of after a destructive push.

**Never** use plain `git push -f` / `--force` against `dev` / `main` without first running `git fetch && git log origin/dev..dev origin/dev` to see what you're about to discard. If you must rewrite history on a shared branch, use `--force-with-lease` so the push fails when the remote has commits you don't.

**Why this rule exists:** 2026-05-28 incident — PR #46 (H-3) and PR #47 (O-11) merged on GitHub at 07:31Z + 07:43Z, but a subsequent local `git push` from a stale `dev` clobbered both merge commits on `origin/dev`. Recovered via `git cherry-pick -m 1 <merge-sha>` of each PR's merge commit. Recovery worked because GitHub preserves the merge SHAs even after the branch ref moves — but it added an hour of triage and a confusing diff state for the in-flight O-9 sprint.

**How to apply:**
- Before any commit on local `dev` / `main`, run `git pull --ff-only origin dev` (or `main`).
- If `--ff-only` refuses (divergence), STOP and figure out why before resolving. Don't reach for `--force` as a shortcut.
- Worktree branches (`sprint/*`, feature branches) don't need this guard — they're owned by you and not shared.
- After running `/sprint-orchestrate`, the wave-N worktrees branch from `origin/dev` directly, so they're isolated from this trap. The trap is on the main checkout's `dev`.
