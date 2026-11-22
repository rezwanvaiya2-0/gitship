# cpanel-deploy

**One-command private GitHub → cPanel deploy tool for shared hosting.**
No root. No SSH key dance. No manual "Pull from Remote" clicking.

```
laptop: git push ──► GitHub ──► webhook ──► your cPanel site (2-5 seconds later) 🎉
```

---

## The problem it solves

Deploying a **private** GitHub repo to cPanel the official way means:

- generating an SSH key in cPanel → SSH Access,
- exporting/authorizing it,
- pasting the public key into GitHub → Deploy keys,
- trusting github.com's host key at some random moment,
- cloning in cPanel → Git Version Control,
- and clicking **Update from Remote** after every single push.

`repo` collapses all of that into **one wizard** that runs in **cPanel → Terminal**
(as your cPanel user — nothing needs root):

```bash
git clone https://github.com/rezwanvaiya2-0/cpanel-deploy.git
cd cpanel-deploy
./repo start
```

You answer 3 questions and paste a temporary GitHub token. The tool:

1. ✔ checks your server (git, curl, php, cPanel `uapi`)
2. ✔ verifies the token + private repo access **before** changing anything
3. ✔ generates an SSH deploy key (`~/.ssh/id_ed25519_<project>`)
4. ✔ adds it to GitHub **via the API automatically** (read-only, this repo only)
5. ✔ pre-trusts github.com's host keys (no scary interactive prompt)
6. ✔ **tests the GitHub ↔ server connection** and shows you the result
7. ✔ clones the repo where you want the site
8. ✔ optionally installs **webhook auto-deploy** (push = live) or a 5-minute cron pull
9. ✔ registers the repo in **cPanel → Git Version Control** via `uapi` —
   it appears in the cPanel UI like any native repo (history, branch switcher,
   Update from Remote — all still work)

At the end you get a summary card with the exact 2 values to paste into GitHub's
webhook settings (if you chose auto-deploy), and a reminder that you can delete
the token — it was used for ~10 seconds and never saved on the server.

---

## Creating the temporary token (the only GitHub-side work)

Open **https://github.com/settings/personal-access-tokens/new** (fine-grained token):

| Setting | Value |
|---|---|
| Token name | anything, e.g. `cpanel-deploy setup` |
| Expiration | shortest you like (it's used once) |
| Repository access | **Only select repositories** → pick your private repo |
| Permissions → Repository | **Administration: Read and write** (adds the deploy key for you) |
| Permissions → Repository | **Contents: Read** |

Generate → copy → paste into `repo start` when asked. Done.

> Prefer the fully manual route? Skip the token and run `repo key` after setup —
> it prints the public key plus exact click-by-click GitHub instructions.

---

## The 4 ways this tool can run

| # | Mode | Updates | Choose when |
|---|------|---------|-------------|
| 1 | **cPanel Git native** ⭐ | cPanel's *Update from Remote* button | you want the familiar cPanel UI |
| 2 | **Mode 1 + webhook** | every `git push` auto-deploys | the best experience (default choice in the wizard) |
| 3 | **cron pull** | checks GitHub every 5 min | webhooks blocked / PHP `exec()` disabled |
| 4 | **manual** | `repo deploy` whenever you say so | full control |

The wizard asks and sets it up. All modes keep the repo visible in
cPanel → Git Version Control (when `uapi` is available).

---

## Command reference

| Command | What it does |
|---|---|
| `repo start` | full setup wizard (see above) |
| `repo status` | **checks the connection right now**: SSH to GitHub, fetch, ahead/behind, auto-update state |
| `repo deploy` | publish now: `git fetch` + `git reset --hard`, logged |
| `repo repair` | fix a diverged/broken tree (cPanel's own `--ff-only` pull refuses to; this one doesn't). `--clean` also removes untracked files (careful: uploads!) |
| `repo rollback [ref]` | temporarily serve an older commit (default `HEAD~1`) — next deploy returns to latest |
| `repo log [n]` | show the deploy log (webhook + cron + manual) |
| `repo key` | show the deploy public key; optionally re-add via the API with a fresh token |
| `repo uninstall` | remove the project's pieces — asks before deleting anything |

Everything is logged to `~/.cpanel-deploy/<project>/deploy.log`.

---

## How auto-deploy works (webhook mode)

`repo start` writes two things:

- `~/public_html/deploy-<random>.php` — the tiny receiver (holds **no secrets**)
- `~/.cpanel-deploy/<project>/deploy.ini` — secret + paths, mode 600, **outside the web root**

The receiver verifies GitHub's `X-Hub-Signature-256` HMAC signature, ignores
anything not signed by GitHub, reacts only to pushes on your branch, and runs:

```bash
git fetch origin <branch> && git reset --hard FETCH_HEAD
```

in the project folder. Because `reset --hard` only touches **tracked** files,
the receiver file and any untracked files (e.g. `.env` you keep on the server)
are never disturbed. Every step is appended to the deploy log — see it with
`repo log`.

cPanel's Git Version Control UI keeps working the whole time; the receiver
keeps the tree clean so the *Update from Remote* button never hits its
`--ff-only` limitation.

---

## Security notes

- The GitHub token is read with hidden input, used for 2 API calls, **never
  written to disk** — delete it after setup, as the summary suggests.
- The deploy key is **read-only** and scoped to **one repo** — even if the
  server is compromised later, there is no GitHub token to steal.
- The webhook rejects unsigned requests (HMAC `sha256` with a 64-hex-char secret).
- The webhook secret + paths live outside the web root with mode 600.
- On cPanel hosts, public access to `.git` directories is already blocked
  globally by cPanel itself.

---

## Troubleshooting

| Symptom | Meaning + fix |
|---|---|
| `401` during token verify | token expired/wrong → make a fresh one, re-run |
| `404` during token verify | repo not selected in the token's *Repository access*, or repo name typo |
| `403` when adding the deploy key | token lacks **Administration: Read and write** |
| "key is already in use" | that SSH key is a deploy key of another repo — that's expected; this tool creates one unique key per project |
| webhook returns `deploy: exec() disabled` | host disabled PHP `exec()` → re-run `repo start` and choose **cron** mode |
| cPanel "Update from Remote" fails | server tree diverged → `repo repair` (it resets cleanly), then the button works again |
| `uapi not found` | not a cPanel session, or restricted shell → finish the wizard and register the repo manually (steps are printed at the end) |
| pushes don't deploy | check `repo status` and `repo log`; confirm the webhook exists in GitHub → Settings → Webhooks and shows green ✓ deliveries |

---

## FAQ

**Does it need root?** No. It runs as your cPanel user; everything lives in
`$HOME` (`~/.ssh`, `~/.cpanel-deploy`, `~/bin`, your web folder).

**Can I deploy several private repos on one server?** Yes — GitHub deploy keys
are one-per-repo, so the tool creates a dedicated key + SSH `Host` alias per
project and runs the wizard once per repo.

**Will my repo still show in cPanel → Git Version Control?** Yes — that's the
point: `repo` registers it via cPanel's own UAPI (`VersionControl::create`).
If `uapi` is unavailable, the final summary prints the 3 fields to enter in the
cPanel UI instead (30 seconds).

**Where is my data?** Project state: `~/.cpanel-deploy/`. SSH keys: `~/.ssh/`.
The `repo` command: `~/bin/repo`. Remove everything per project with `repo uninstall`.
