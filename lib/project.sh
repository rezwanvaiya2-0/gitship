# ============================================================================
#  project.sh — per-project state (~/.cpanel-deploy/<slug>.conf) and the git
#  operations behind deploy / status / repair / rollback.
#
#  Deploy strategy: `git fetch origin <branch>` + `git reset --hard FETCH_HEAD`.
#  This is deliberately stronger than cPanel's own `--ff-only` pull: it can
#  never be blocked by a diverged working tree, so cPanel's UI never breaks.
# ============================================================================

DEPLOY_STATE_DIR="${HOME}/.cpanel-deploy"

# All keys persisted per project (order = save_conf output order)
CONF_KEYS="SLUG OWNER REPO BRANCH REPO_PATH CLONE_URL SSH_ALIAS SSH_KEY WEBHOOK_SECRET WEBHOOK_PHP CRON_SH DEPLOY_LOG LOCK_FILE INI_FILE"

current_slug() {
  [ -f "$DEPLOY_STATE_DIR/current" ] && cat "$DEPLOY_STATE_DIR/current"
  return 0
}

conf_path_for_slug() {
  printf '%s/%s.conf' "$DEPLOY_STATE_DIR" "$1"
}

# load_conf SLUG — sources the conf file, then applies safe defaults
load_conf() {
  local _f
  _f=$(conf_path_for_slug "$1")
  [ -f "$_f" ] || return 1
  . "$_f"
  [ -n "${DEPLOY_LOG:-}" ]  || DEPLOY_LOG="$DEPLOY_STATE_DIR/$SLUG/deploy.log"
  [ -n "${LOCK_FILE:-}" ]   || LOCK_FILE="$DEPLOY_STATE_DIR/$SLUG/deploy.lock"
  [ -n "${INI_FILE:-}" ]    || INI_FILE="$DEPLOY_STATE_DIR/$SLUG/deploy.ini"
  return 0
}

# save_conf SLUG — persists the CONF_KEYS globals (mode 600)
save_conf() {
  local _slug="$1" _f _tmp _k _v
  _f=$(conf_path_for_slug "$_slug")
  mkdir -p "$DEPLOY_STATE_DIR" 2>/dev/null
  chmod 700 "$DEPLOY_STATE_DIR" 2>/dev/null
  _tmp="$_f.tmp"
  : > "$_tmp"
  for _k in $CONF_KEYS; do
    eval "_v=\"\$$_k\"" 2>/dev/null || _v=""
    printf '%s="%s"\n' "$_k" "$(printf '%s' "${_v:-}" | sed 's/"/\\"/g')" >> "$_tmp"
  done
  mv "$_tmp" "$_f"
  chmod 600 "$_f"
  printf '%s' "$_slug" > "$DEPLOY_STATE_DIR/current"
}

ensure_state_dir() {
  mkdir -p "$DEPLOY_STATE_DIR/$SLUG" 2>/dev/null
  chmod 700 "$DEPLOY_STATE_DIR" 2>/dev/null
  [ -f "$DEPLOY_LOG" ]  || : > "$DEPLOY_LOG"
  chmod 600 "$DEPLOY_LOG" 2>/dev/null
}

git_in_project() { # git args..., using the project's .git dir
  git --git-dir="$REPO_PATH/.git" "$@"
}

# clone_project CLONE_URL PATH BRANCH
clone_project() {
  local _url="$1" _path="$2" _branch="$3"
  if [ -e "$_path" ] && [ -n "$(ls -A "$_path" 2>/dev/null)" ]; then
    die "Target path already exists and is not empty: $_path
Choose another path, or remove the old folder first."
  fi
  info "Cloning (this may take a moment)..."
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "[dry-run] git clone --branch $_branch --single-branch $_url $_path"
    return 0
  fi
  git clone --branch "$_branch" --single-branch "$_url" "$_path" >/dev/null 2>&1 \
    || die "git clone failed.
Run it manually to see the real error:
  git clone --branch '$_branch' '$_url' '$_path'"
  ok "Cloned to: $_path"
}

# deploy_update — fetch + reset, appending everything to the deploy log
deploy_update() {
  local _t _rc
  [ -d "$REPO_PATH/.git" ] || die "Not a git repository: $REPO_PATH"
  ensure_state_dir
  _t=$(date '+%Y-%m-%d %H:%M:%S')
  info "Deploying $OWNER/$REPO (branch: $BRANCH) -> $REPO_PATH"
  {
    printf '[%s] DEPLOY started by %s\n' "$_t" "$(whoami 2>/dev/null || echo user)"
    git_in_project fetch origin "$BRANCH" 2>&1
  } >> "$DEPLOY_LOG" || {
    printf '[%s] FETCH FAILED\n' "$_t" >> "$DEPLOY_LOG"
    die "git fetch failed — full error in: $DEPLOY_LOG"
  }
  git_in_project reset --hard FETCH_HEAD >> "$DEPLOY_LOG" 2>&1 || {
    printf '[%s] RESET FAILED\n' "$_t" >> "$DEPLOY_LOG"
    die "git reset failed — full error in: $DEPLOY_LOG"
  }
  printf '[%s] DEPLOY OK %s/%s@%s\n' "$_t" "$OWNER" "$REPO" \
    "$(git_in_project rev-parse --short HEAD 2>/dev/null)" >> "$DEPLOY_LOG"
  ok "Deployed."
  ok "Now serving: $(git_in_project log -1 --oneline 2>/dev/null)"
}

# status_counts — fetches origin and sets AHEAD / BEHIND / FETCH_FAILED
status_counts() {
  FETCH_FAILED=0; AHEAD=0; BEHIND=0
  local _c
  git_in_project fetch origin "$BRANCH" >/dev/null 2>&1 || { FETCH_FAILED=1; return; }
  _c=$(git_in_project rev-list --left-right --count "HEAD...origin/$BRANCH" 2>/dev/null)
  AHEAD=$(printf '%s' "$_c" | cut -f1)
  BEHIND=$(printf '%s' "$_c" | cut -f2)
  [ -n "$AHEAD" ]  || AHEAD=0
  [ -n "$BEHIND" ] || BEHIND=0
}

# install_self_to_bin — makes `repo` callable from anywhere on cPanel Terminal
install_self_to_bin() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "[dry-run] install: ~/bin/repo -> $REPO_TOOL_DIR/repo"
    return 0
  fi
  mkdir -p "$HOME/bin"
  ln -sfn "$REPO_TOOL_DIR/repo" "$HOME/bin/repo" 2>/dev/null \
    || cp -f "$REPO_TOOL_DIR/repo" "$HOME/bin/repo"
  case ":$PATH:" in
    *":$HOME/bin:"*)
      ok "'repo' command installed at ~/bin/repo (on PATH) — works from any folder"
      ;;
    *)
      warn "'repo' installed at ~/bin/repo, but ~/bin is not on your PATH."
      dim  "Fix now:   export PATH=\"\$HOME/bin:\$PATH\""
      dim  "For every future session add that line to ~/.bashrc"
      ;;
  esac
}
