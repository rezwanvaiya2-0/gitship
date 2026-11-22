# gitship

**Set up private GitHub repos on cPanel shared hosting — perfectly, in one command.**
No root. No SSH key dance. Afterwards everything is managed in the **familiar cPanel UI**.

```
laptop: git push ──► GitHub
cPanel → Git Version Control → Update from Remote ──► live site ✅
```

---

## The problem it solves

Deploying a **private** GitHub repo to cPanel the official way means:

- generating an SSH key in cPanel → SSH Access,
- exporting/authorizing it,
- pasting the public key into GitHub → Deploy keys,
- trusting github.com's host key at some random moment,
- cloning in cPanel → Git Version Control,
- and getting every one of those steps right, in order.

`gitship` collapses all of that into **one wizard** that runs in **cPanel → Terminal**
(as your cPanel user — nothing needs root):

```bash
git clone https://github.com/rezwanvaiya2-0/gitship.git
cd gitship
./repo start
```

You answer 3 questions and paste a temporary GitHub token. The tool:

1. ✔ checks your server (git, curl, php, cPanel `uapi`)
2. ✔ verifies the token + private repo access **before** changing anything
3. ✔ generates an SSH deploy key — **through cPanel itself** when `cpapi2` is
   available, so it shows up in **cPanel → SSH Access → Manage SSH Keys**
   (`~/.ssh/cpanel_deploy_<project>`); falls back to a local ed25519 key otherwise
4. ✔ adds the deploy key to GitHub **via the API automatically** (read-only,
   this repo only — the token is used for ~10 seconds and never saved on the server)
5. ✔ pre-trusts github.com's host keys (no scary interactive prompt)
6. ✔ **tests the GitHub ↔ server connection** and shows you the result
7. ✔ clones the repo where you want the site
8. ✔ registers it in **cPanel → Git Version Control** via `uapi` and **verifies**
   it actually appears there

The final summary card tells you: what was installed, where the files live,
how to publish updates, and that you can delete the token now.

---

## Creating the temporary token (the only GitHub-side work)

Open **https://github.com/settings/personal-access-tokens/new** (fine-grained token):

| Setting | Value |
|---|---|
| Token name | anything, e.g. `gitship setup` |
| Expiration | shortest you like (it's used once) |
| Repository access | **Only select repositories** → pick your private repo |
| Permissions → Repository | **Administration: Read and write** (adds the deploy key for you) |
| Permissions → Repository | **Contents: Read** |

Generate → copy → paste into `repo start` when asked. Done.

> Prefer the fully manual route? Skip the token and run `repo key` after setup —
> it prints the public key plus exact click-by-click GitHub instructions.

---

## How updates work — 100% cPanel native

After setup, your repo is a **completely normal cPanel-managed Git repository**:

- It appears in **cPanel → Git Version Control** with history (Gitweb), branch
  switcher and the **Update from Remote** button
- **Publishing = one click** on *Update from Remote* after you `git push`
- Power users can skip the click: **`repo deploy`** does the same pull from
  Terminal — but stronger (see below)

**Why the helpers exist:** cPanel's own button pulls with `--ff-only`, so it
refuses to update when the server tree ever diverges. gitship's `repo repair`
fixes that state, and `repo deploy` uses `fetch + reset --hard` so it can't get
blocked in the first place.

---

## Command reference

| Command | What it does |
|---|---|
| `repo start` | full setup wizard (see above) |
| `repo register` | (re)register the current project in cPanel → Git Version Control, then **verify** it actually appears there |
| `repo status` | **checks the connection right now**: SSH to GitHub, fetch, ahead/behind, cPanel listing |
| `repo deploy` | publish now: `git fetch` + `git reset --hard`, logged |
| `repo repair` | fix a diverged/broken tree so cPanel's button works again. `--clean` also removes untracked files (careful: uploads!) |
| `repo rollback [ref]` | temporarily serve an older commit (default `HEAD~1`) — next deploy returns to latest |
| `repo log [n]` | show the deploy log |
| `repo key` | show the deploy public key; re-add it to GitHub via the API, and/or register it in cPanel → SSH Access so it shows under **Manage SSH Keys** |
| `repo uninstall` | remove the project's pieces — asks before deleting anything |

Everything is logged to `~/.cpanel-deploy/<project>/deploy.log`.

---

## The tool is only the installer — your repo stays independent

After `repo start` finishes, your repo is a **completely normal cPanel-managed
Git repository**. Everything keeps working whether or not this tool remains:

- cPanel → Git Version Control manages it natively — registered through
  cPanel's own UAPI (`VersionControl::create`)
- The remote URL is the clean, standard `git@github.com:owner/repo.git` for
  your first project (a per-project SSH alias is used automatically when you
  add a second project, since GitHub deploy keys are repo-scoped)
- The SSH deploy key lives in `~/.ssh/` and works with or without this tool
- `repo uninstall` asks before removing each piece. Site files are only
  deleted after a double confirmation.

---

## Security notes

- The GitHub token is read with hidden input, used for 2 API calls, **never
  written to disk** — delete it after setup, as the summary suggests.
- The deploy key is **read-only** and scoped to **one repo** — even if the
  server is compromised later, there is no GitHub token to steal.
- On cPanel hosts, public access to `.git` directories is already blocked
  globally by cPanel itself.
- Keys created through cPanel (API 2 `SSH::genkey`) are listed in
  **SSH Access → Manage SSH Keys**; they show as *not authorized* — that is
  normal: authorization only applies to people logging **into** the server,
  while deploy keys connect **out** to GitHub.

---

## Troubleshooting

| Symptom | Meaning + fix |
|---|---|
| `401` during token verify | token expired/wrong → make a fresh one, re-run |
| `404` during token verify | repo not selected in the token's *Repository access*, or repo name typo |
| `403` when adding the deploy key | token lacks **Administration: Read and write** |
| "key is already in use" | that SSH key is a deploy key of another repo — expected; this tool creates one unique key per project |
| cPanel "Update from Remote" fails | server tree diverged → `repo repair` (it resets cleanly), then the button works again |
| repo missing in cPanel → Git Version Control | registration failed or was interrupted → update the tool (`git pull` in its folder) and run `repo register`; full uapi output is printed if it fails again |
| deploy key not visible in cPanel → SSH Access | update the tool (`git pull`), then run `repo key` and choose the cPanel registration option |
| `uapi not found` | not a cPanel session, or restricted shell → finish the wizard and register the repo manually (steps are printed at the end) |

---

## FAQ

**Does it need root?** No. It runs as your cPanel user; everything lives in
`$HOME` (`~/.ssh`, `~/.cpanel-deploy`, `~/bin`, your web folder).

**Can I deploy several private repos on one server?** Yes — GitHub deploy keys
are one-per-repo, so the tool creates a dedicated key + SSH `Host` entry per
project and runs the wizard once per repo.

**Will my repo still show in cPanel → Git Version Control?** Yes — that's the
point: `repo` registers it via cPanel's own UAPI. If `uapi` is unavailable, the
final summary prints the 3 fields to enter in the cPanel UI instead (30 seconds).

**Why no auto-deploy on push?** gitship is deliberately **cPanel-native**: your
repo is managed exactly like any other cPanel Git repo, and publishing is the
one-click *Update from Remote* button. No extra moving parts, nothing that can
silently break — and the tool itself can be deleted without affecting your site.

**Where do I see the SSH deploy key in cPanel?**
cPanel → Security → **SSH Access** → **Manage SSH Keys** — look for the key
named `cpanel_deploy_<project>`. Keys created by `repo start` are generated
through cPanel so they appear there natively; keys generated by older versions
of the tool can be registered for visibility with `repo key`.

**Where is my data?** Project state: `~/.cpanel-deploy/`. SSH keys: `~/.ssh/`.
The `repo` command: `~/bin/repo`. Remove everything per project with `repo uninstall`.
