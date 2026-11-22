# ============================================================================
#  commands.sh — the repo subcommands (start / status / deploy / repair /
#  rollback / log / key / uninstall / selftest)
# ============================================================================

DRY_RUN=0

# run_wrap DESC CMD ARGS... — dry-run aware executor for mutating steps
run_wrap() {
  local _desc="$1"; shift
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "[dry-run] $_desc"
    return 0
  fi
  "$@"
}

# ----------------------------------------------------------------------------
# repo start — the full wizard
# ----------------------------------------------------------------------------
cmd_start() {
  local _url_in="" _branch_in="" _path_in="" _url="" _mode="manual" _in_webroot=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)    _url_in="$2";    shift 2 ;;
      --branch)  _branch_in="$2"; shift 2 ;;
      --path)    _path_in="$2";   shift 2 ;;
      --dry-run) DRY_RUN=1;       shift ;;
      *) warn "unknown option ignored: $1"; shift ;;
    esac
  done

  banner
  if [ "$DRY_RUN" = "1" ]; then
    warn "DRY-RUN MODE: nothing will be changed on this server (still needs network for checks)."
  fi

  # ---- 1/7 environment -------------------------------------------------------
  step "1/7  Checking your server (running as your cPanel user - no root needed)"
  command -v git >/dev/null 2>&1 \
    || die "git is not available on this server.
Most cPanel hosts ship it. Ask your host to enable git, or use the
cron+zipball fallback described in README.md."
  ok "git: $(git --version)"
  command -v curl >/dev/null 2>&1 || die "curl is required but missing on this server."
  ok "curl: available"
  if command -v php >/dev/null 2>&1; then
    ok "php: $(php -r 'echo PHP_VERSION;' 2>/dev/null || php --version 2>/dev/null | head -n 1)"
  else
    warn "php CLI not found - webhook mode may still work through the web server."
  fi
  if detect_uapi; then
    ok "cPanel uapi: found — automatic Git Version Control registration available"
  else
    warn "uapi not found — is this really a cPanel session? Registration will be guided manually."
  fi
  if [ -n "${CPANEL_DEPLOY_TOKEN:-}" ]; then
    GIT_TOKEN="$CPANEL_DEPLOY_TOKEN"
    ok "GitHub token provided via CPANEL_DEPLOY_TOKEN environment variable"
  fi

  # ---- 2/7 repo + token ------------------------------------------------------
  step "2/7  Your private repository"
  if [ -n "$_url_in" ]; then
    _url="$_url_in"
  else
    ask _url "Private repo URL  (git@github.com:you/app.git, https://github.com/you/app, or you/app)"
  fi
  [ -n "$_url" ] || die "Repository URL is required."
  parse_owner_repo "$_url" \
    || die "Could not understand that GitHub URL: '$_url'
Examples:  git@github.com:owner/repo.git  |  https://github.com/owner/repo  |  owner/repo"
  ok "Repository: $OWNER/$REPO"
  SLUG=$(slugify "$REPO")
  [ -n "$SLUG" ] || die "Could not make a project name from '$REPO'."
  if [ -f "$(conf_path_for_slug "$SLUG")" ]; then
    die "Project '$SLUG' is already set up on this server.
Inspect it:  repo status $SLUG        Remove it:  repo uninstall $SLUG"
  fi
  if [ -z "$GIT_TOKEN" ]; then
    echo
    info "A temporary GitHub token lets me add the SSH deploy key FOR you."
    info "It is used for ~10 seconds, never saved on this server, and you can"
    info "delete it right after setup."
    dim "  1. Open:  https://github.com/settings/personal-access-tokens/new"
    dim "  2. Repository access -> 'Only select repositories' -> pick $OWNER/$REPO"
    dim "  3. Permissions -> Repository permissions -> set:"
    dim "       Administration : Read and write   (adds the deploy key automatically)"
    dim "       Contents       : Read"
    dim "  4. Generate token -> copy it -> paste it below."
    echo
    ask_secret GIT_TOKEN "Paste the GitHub token"
    [ -n "$GIT_TOKEN" ] || die "No token given - cannot add the deploy key automatically.
Manual path: finish setup, then run 'repo key' for copy-paste instructions."
  fi
  info "Verifying token + repository access..."
  verify_repo_access "$OWNER" "$REPO"
  ok "Token verified - repository reachable, default branch: $GH_DEFAULT_BRANCH"

  # ---- 3/7 SSH deploy key ----------------------------------------------------
  step "3/7  SSH deploy key (automatic - replaces the whole manual SSH dance)"
  SSH_KEY="$HOME/.ssh/id_ed25519_$SLUG"
  SSH_ALIAS="github-$SLUG"
  run_wrap "generate SSH key $SSH_KEY" gen_deploy_key "$SSH_KEY"
  run_wrap "write ~/.ssh/config block (Host $SSH_ALIAS)" \
           write_ssh_config_block "$SSH_ALIAS" "$SSH_KEY" "$SLUG"
  run_wrap "pre-trust github.com in known_hosts" seed_known_hosts
  if [ "$DRY_RUN" != "1" ]; then
    PUBKEY=$(cat "$SSH_KEY.pub" 2>/dev/null) || die "Deploy key public file missing: $SSH_KEY.pub"
    HOSTN=$(hostname 2>/dev/null || echo cpanel)
    info "Adding read-only deploy key to $OWNER/$REPO via the GitHub API..."
    add_deploy_key "$OWNER" "$REPO" "$PUBKEY" "cpanel-deploy $HOSTN $(date +%Y-%m-%d)" \
      || die "Could not add the deploy key (see the message above).
Manual path: run 'repo key' - it prints the key + exact GitHub steps."
    ok "Deploy key added to GitHub (read-only, this repo only)"
    info "Testing the GitHub <-> server SSH connection..."
    if ssh_auth_test "$SSH_ALIAS"; then
      ok "GitHub accepts this server's key: $(printf '%s' "$SSH_TEST_OUT" | head -n 1)"
    else
      die "SSH connection test FAILED even though the key was added.
GitHub said: $SSH_TEST_OUT
Sometimes GitHub needs a moment - re-run in 10s:  repo status"
    fi
  fi

  # ---- 4/7 location ----------------------------------------------------------
  step "4/7  Where should the site files live?"
  if [ -n "$_path_in" ]; then
    REPO_PATH="$_path_in"
  else
    ask REPO_PATH "Full path for this deployment" "$HOME/public_html/$SLUG"
  fi
  REPO_PATH=$(printf '%s' "$REPO_PATH" | sed "s|^~|$HOME|")
  case "$REPO_PATH" in
    /*) : ;;
    *)  REPO_PATH="$HOME/$REPO_PATH" ;;
  esac
  if [ -n "$_branch_in" ]; then
    BRANCH="$_branch_in"
  else
    ask BRANCH "Branch to deploy" "$GH_DEFAULT_BRANCH"
  fi
  [ -n "$BRANCH" ] || BRANCH="$GH_DEFAULT_BRANCH"

  # ---- 5/7 clone -------------------------------------------------------------
  step "5/7  Cloning your private repository"
  CLONE_URL="git@$SSH_ALIAS:$OWNER/$REPO.git"
  clone_project "$CLONE_URL" "$REPO_PATH" "$BRANCH"

  # ---- 6/7 update mode -------------------------------------------------------
  DEPLOY_LOG="$DEPLOY_STATE_DIR/$SLUG/deploy.log"
  LOCK_FILE="$DEPLOY_STATE_DIR/$SLUG/deploy.lock"
  ensure_state_dir
  step "6/7  How should updates arrive after you git push?"
  WEBHOOK_SECRET=""; WEBHOOK_PHP=""; CRON_SH=""; INI_FILE=""
  case "$REPO_PATH" in "$HOME/public_html"|"$HOME/public_html"/*) _in_webroot=1 ;; esac
  if [ "$_in_webroot" = "1" ]; then
    if confirm "Install webhook AUTO-DEPLOY? (every git push updates the live site in seconds)" "y"; then
      if webhook_install; then
        _mode="webhook"
      else
        warn "Webhook install failed - falling back."
      fi
    fi
  else
    warn "Repo is outside ~/public_html, so a webhook cannot reach it. Use cron or manual mode."
  fi
  if [ "$_mode" = "manual" ] && confirm "Install a CRON auto-pull? (checks GitHub every 5 minutes via cPanel -> Cron Jobs)" "y"; then
    cron_install && _mode="cron"
  fi
  case "$_mode" in
    webhook) ok "Auto-update on push: WEBHOOK (push = live)" ;;
    cron)    ok "Auto-update: CRON every 5 minutes" ;;
    *)       info "Manual mode chosen: run 'repo deploy' whenever you want to publish." ;;
  esac

  # ---- 7/7 cPanel registration ----------------------------------------------
  step "7/7  Registering with cPanel -> Git Version Control"
  CPANEL_REG=0
  if detect_uapi; then
    info "Calling: uapi VersionControl create ..."
    if [ "$DRY_RUN" = "1" ]; then
      dim "[dry-run] $UAPI_BIN VersionControl create repository_path=$REPO_PATH repository_name=$REPO"
    elif cpanel_register_repo "$REPO_PATH" "$REPO"; then
      CPANEL_REG=1
      ok "Registered - the repo now appears in cPanel -> Git Version Control"
    else
      warn "Automatic registration did not succeed. uapi output:"
      dim "$(printf '%s' "${UAPI_OUT:-}" | head -c 400)"
    fi
  fi
  if [ "$CPANEL_REG" = "0" ] && [ "$DRY_RUN" != "1" ]; then
    info "Register it manually in 30 seconds (cPanel -> Git Version Control -> Create):"
    dim "  - Clone a Repository : OFF (the repo already exists on disk)"
    dim "  - Repository Path    : $REPO_PATH"
    dim "  - Repository Name    : $REPO"
    dim "  (cPanel will detect the existing repo and adopt it)"
  fi

  # ---- save state + helper command + summary ---------------------------------
  if [ "$DRY_RUN" = "1" ]; then
    run_wrap "save project config to $(conf_path_for_slug "$SLUG")" save_conf "$SLUG"
    run_wrap "install 'repo' command into ~/bin" install_self_to_bin
    step "Dry-run finished - nothing was changed."
    return 0
  fi
  save_conf "$SLUG"
  install_self_to_bin
  print_summary "$_mode" "$CPANEL_REG"
}

# ----------------------------------------------------------------------------
# summary card (end of repo start)
# ----------------------------------------------------------------------------
print_summary() {
  local _mode="$1" _cpreg="$2" _domain _whname
  echo
  step "Setup complete - summary"
  print_row "Project" "$SLUG ($OWNER/$REPO)"
  print_row "Branch" "$BRANCH"
  print_row "Server path" "$REPO_PATH"
  print_row "Deploy key" "$SSH_KEY (read-only, this repo only)"
  if [ "$_cpreg" = "1" ]; then
    print_row "cPanel Git" "registered - manage it in cPanel -> Git Version Control"
  else
    print_row "cPanel Git" "not registered (manual steps above)"
  fi
  case "$_mode" in
    webhook)
      _domain=$(detect_main_domain 2>/dev/null)
      [ -n "$_domain" ] || _domain="YOUR-DOMAIN"
      _whname=$(basename "$WEBHOOK_PHP")
      print_row "Auto-update" "webhook: every git push = live site"
      print_row "Deploy log" "$DEPLOY_LOG"
      echo
      info "LAST STEP - add the webhook in GitHub (2 values to copy):"
      dim "  $OWNER/$REPO -> Settings -> Webhooks -> Add webhook"
      dim "    Payload URL  : https://$_domain/$_whname"
      dim "    Content type : application/json"
      dim "    Secret       : $WEBHOOK_SECRET"
      dim "    (keep the default trigger: 'Just the push event')"
      ;;
    cron)
      print_row "Auto-update" "cron - add this line in cPanel -> Cron Jobs -> New Cron Job:"
      dim "  */5 * * * * $CRON_SH >/dev/null 2>&1"
      print_row "Deploy log" "$DEPLOY_LOG"
      ;;
    *)
      print_row "Auto-update" "manual - publish anytime with:  repo deploy"
      print_row "Deploy log" "$DEPLOY_LOG"
      ;;
  esac
  echo
  hr
  warn "You can DELETE the GitHub token now - it was never saved on this server."
  ok "Check the connection anytime:   repo status"
  ok "Publish manually anytime:       repo deploy"
  echo
}

# ----------------------------------------------------------------------------
# repo status — the connection checker
# ----------------------------------------------------------------------------
cmd_status() {
  load_current_or_die "$1"
  printf '\n%srepo status%s — %s/%s (branch: %s)\n' "$C_TITLE" "$C_RESET" "$OWNER" "$REPO" "$BRANCH"
  hr
  if [ -f "$SSH_KEY" ] && ssh_auth_test "$SSH_ALIAS"; then
    ok "GitHub SSH connection: OK"
  else
    err "GitHub SSH connection: FAILED"
    dim "GitHub said: $(printf '%s' "${SSH_TEST_OUT:-}" | head -n 2)"
    dim "Fix: run 'repo key' (re-add the deploy key), then 'repo status' again."
  fi
  if [ ! -d "$REPO_PATH/.git" ]; then
    err "Deploy folder missing or not a git repository: $REPO_PATH"
    return 1
  fi
  status_counts
  if [ "$FETCH_FAILED" = "1" ]; then
    err "git fetch from GitHub FAILED (connection or repository problem)"
  elif [ "$BEHIND" = "0" ] && [ "$AHEAD" = "0" ]; then
    ok "Server matches GitHub (nothing behind, nothing ahead)"
  else
    [ "$BEHIND" != "0" ] && warn "Server is $BEHIND commit(s) BEHIND GitHub - publish with: repo deploy"
    [ "$AHEAD"  != "0" ] && warn "Server has $AHEAD commit(s) that GitHub does not have"
  fi
  ok "HEAD: $(git_in_project log -1 --oneline 2>/dev/null)"
  if [ -n "$WEBHOOK_PHP" ] && [ -f "$WEBHOOK_PHP" ]; then
    ok "Auto-update on push: ON ($WEBHOOK_PHP)"
  elif [ -n "$CRON_SH" ] && [ -f "$CRON_SH" ]; then
    ok "Auto-update: ON (cron - $CRON_SH)"
  else
    dim "Auto-update: manual (repo deploy)"
  fi
  if [ -f "$DEPLOY_LOG" ] && [ -s "$DEPLOY_LOG" ]; then
    info "Last log entry: $(tail -n 1 "$DEPLOY_LOG")"
  fi
  echo
}

# ----------------------------------------------------------------------------
# repo deploy / repair / rollback / log / key / uninstall
# ----------------------------------------------------------------------------
cmd_deploy() {
  load_current_or_die "$1"
  deploy_update
}

cmd_repair() {
  load_current_or_die ""
  local _clean=0
  [ "${1:-}" = "--clean" ] && _clean=1
  warn "Repair = fetch + 'git reset --hard origin/$BRANCH'."
  warn "Any edits made directly on the server WILL BE DISCARDED."
  confirm "Proceed?" "n" || { dim "aborted."; return 1; }
  ensure_state_dir
  printf '[%s] REPAIR started\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DEPLOY_LOG"
  git_in_project fetch origin "$BRANCH" >> "$DEPLOY_LOG" 2>&1 \
    || die "git fetch failed - see: $DEPLOY_LOG"
  git_in_project reset --hard "origin/$BRANCH" >> "$DEPLOY_LOG" 2>&1 \
    || die "git reset failed - see: $DEPLOY_LOG"
  if [ "$_clean" = "1" ]; then
    warn "--clean also DELETES untracked files (uploads, caches, logs...)."
    confirm "Really delete untracked files under $REPO_PATH?" "n" && \
      git_in_project clean -fd >> "$DEPLOY_LOG" 2>&1
  fi
  printf '[%s] REPAIR OK\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DEPLOY_LOG"
  ok "Repaired. Now serving: $(git_in_project log -1 --oneline 2>/dev/null)"
}

cmd_rollback() {
  load_current_or_die ""
  local _to="${1:-HEAD~1}"
  warn "Rolling back live files to: $_to"
  dim "Note: the next successful push/webhook/cron deploy returns the site to latest."
  confirm "Proceed?" "n" || { dim "aborted."; return 1; }
  git_in_project reset --hard "$_to" >/dev/null 2>&1 \
    || die "Could not reset to '$_to'. Wrong ref? Try:  repo rollback origin/$BRANCH~1"
  printf '[%s] ROLLBACK to %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_to" >> "$DEPLOY_LOG"
  ok "Rolled back. Now serving: $(git_in_project log -1 --oneline 2>/dev/null)"
}

cmd_log() {
  load_current_or_die ""
  [ -f "$DEPLOY_LOG" ] || { dim "No deploy log yet: $DEPLOY_LOG"; return 0; }
  hr
  tail -n "${1:-50}" "$DEPLOY_LOG"
  hr
}

cmd_key() {
  load_current_or_die "$1"
  [ -f "$SSH_KEY.pub" ] || die "No SSH key found for this project: $SSH_KEY.pub"
  echo
  info "Deploy key public part for $OWNER/$REPO:"
  dim "(GitHub -> $OWNER/$REPO -> Settings -> Deploy keys -> Add deploy key,"
  dim " paste it, and LEAVE 'Allow write access' UNCHECKED)"
  echo
  cat "$SSH_KEY.pub"
  echo
  if confirm "Add it via the GitHub API now? (needs a temporary token: Administration: Read and write)" "n"; then
    ask_secret GIT_TOKEN "GitHub token"
    [ -n "$GIT_TOKEN" ] || { dim "no token - skipped."; return 1; }
    verify_repo_access "$OWNER" "$REPO"
    HOSTN=$(hostname 2>/dev/null || echo cpanel)
    if add_deploy_key "$OWNER" "$REPO" "$(cat "$SSH_KEY.pub")" \
         "cpanel-deploy $HOSTN $(date +%Y-%m-%d)"; then
      ok "Deploy key added. Testing connection..."
      if ssh_auth_test "$SSH_ALIAS"; then
        ok "Connection OK - $(printf '%s' "$SSH_TEST_OUT" | head -n 1)"
      else
        warn "Key added but SSH test failed. Wait 10s, then: repo status"
      fi
    else
      warn "Deploy key was not added (see message above)."
    fi
  fi
}

cmd_uninstall() {
  load_current_or_die "$1"
  echo
  warn "Uninstall plan for project '$SLUG':"
  info "1. remove webhook receiver (if any):  ${WEBHOOK_PHP:-none}"
  info "2. remove cron script (if any):       ${CRON_SH:-none}"
  info "3. remove tool state:                 $DEPLOY_STATE_DIR/$SLUG*"
  info "4. optionally: remove from cPanel Git Version Control (files stay)"
  info "5. optionally: delete the SSH key + ~/.ssh/config block"
  info "6. optionally: DELETE the cloned files at $REPO_PATH"
  echo
  dim "GitHub side is NOT automatic here: remove the deploy key manually at"
  dim "github.com/$OWNER/$REPO -> Settings -> Deploy keys -> remove 'cpanel-deploy ...'"
  echo
  confirm "Start uninstall?" "n" || { dim "aborted."; return 1; }

  if [ -n "$WEBHOOK_PHP" ] && [ -f "$WEBHOOK_PHP" ]; then
    rm -f "$WEBHOOK_PHP" && ok "Removed webhook receiver: $WEBHOOK_PHP"
  fi
  if [ -n "$CRON_SH" ] && [ -f "$CRON_SH" ]; then
    rm -f "$CRON_SH" && ok "Removed cron script: $CRON_SH"
    warn "Also remove its line in cPanel -> Cron Jobs (elsewise harmless, but clean it):"
    dim "  */5 * * * * $CRON_SH >/dev/null 2>&1"
  fi
  if detect_uapi && confirm "Remove from cPanel Git Version Control? (your files are NOT deleted)" "y"; then
    if cpanel_remove_repo "$REPO_PATH"; then
      ok "Removed from cPanel's managed repositories."
    else
      warn "cPanel removal failed - remove it manually in the Git Version Control UI."
    fi
  fi
  if confirm "Delete the SSH deploy key + ssh config block for this project?" "n"; then
    rm -f "$SSH_KEY" "$SSH_KEY.pub"
    remove_ssh_config_block "$SLUG"
    ok "SSH key + config block removed."
  fi
  if confirm "DELETE the cloned files at $REPO_PATH? (CANNOT BE UNDONE)" "n"; then
    if confirm "Last check - really delete ALL files in $REPO_PATH?" "n"; then
      rm -rf "$REPO_PATH" && ok "Deleted: $REPO_PATH"
    fi
  fi
  rm -rf "$DEPLOY_STATE_DIR/$SLUG"
  rm -f "$(conf_path_for_slug "$SLUG")"
  : > "$DEPLOY_STATE_DIR/current" 2>/dev/null
  ok "Project '$SLUG' uninstalled."
}

# ----------------------------------------------------------------------------
# repo selftest — internal checks (development)
# ----------------------------------------------------------------------------
cmd_selftest() {
  _fail=0
  t() {
    if [ "$2" = "$3" ]; then ok "$1"; else err "$1 — expected [$2] got [$3]"; _fail=1; fi
  }

  parse_owner_repo "git@github.com:foo/bar.git";       t "parse scp-style"        "foo|bar" "$OWNER|$REPO"
  parse_owner_repo "https://github.com/foo/bar/";      t "parse https + slash"    "foo|bar" "$OWNER|$REPO"
  parse_owner_repo "https://github.com/foo/bar.git";   t "parse https + .git"     "foo|bar" "$OWNER|$REPO"
  parse_owner_repo "ssh://git@github.com/foo/bar.git"; t "parse ssh://"           "foo|bar" "$OWNER|$REPO"
  parse_owner_repo "foo/bar";                          t "parse owner/repo"       "foo|bar" "$OWNER|$REPO"
  if parse_owner_repo "https://gitlab.com/foo/bar" 2>/dev/null; then
    err "non-github URL should be rejected"; _fail=1
  else
    ok "non-github URL rejected"
  fi

  t "slugify 'My App!'"          "my-app"   "$(slugify 'My App!')"
  t "gen_hex 4 length"           "8"        "$(gen_hex 4 | wc -c | tr -d ' ')"
  t "json_str escapes quotes"    '"a\"b"'   "$(json_str 'a"b')"

  GH_BODY='{
  "ssh_keys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZmV7ZmyWOSlugLJIqjK6JvGnyFPBxU1EMKfxUzDpnrKSiri5o7EbXzT5PVgTBOwgPEnQbAo=",
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDRqhmYuFovtYmWjpXb6RuVfGbJClRE7vVneBpCYKCGWlrRQvMFHmMF"
  ]}'
  t "ssh key parser count" "3" "$(parse_ssh_keys_from_json | wc -l | tr -d ' ')"

  _tmp=$(mktemp -d)
  sed "s|{{CONF_FILE}}|/home/x/.cpanel-deploy/t/deploy.ini|g" \
      "$REPO_TOOL_DIR/templates/deploy.php.tpl" > "$_tmp/d.php"
  grep -q '/home/x/.cpanel-deploy/t/deploy.ini' "$_tmp/d.php"
  t "deploy.php template render" "0" "$?"
  if command -v php >/dev/null 2>&1; then
    php -l "$_tmp/d.php" >/dev/null 2>&1
    t "php -l deploy.php" "0" "$?"
  fi

  _oldcur=$(current_slug)
  SLUG="t" OWNER="o" REPO="r" BRANCH="main" REPO_PATH="/tmp/pp" CLONE_URL="git@a:r.git" \
  SSH_ALIAS="github-t" SSH_KEY="/k" WEBHOOK_SECRET="s3cret" WEBHOOK_PHP="/d.php" \
  CRON_SH="" DEPLOY_LOG="/l.log" LOCK_FILE="/l.lock" INI_FILE="/i.ini"
  save_conf "t"
  load_conf "t"
  t "conf roundtrip secret" "s3cret" "$WEBHOOK_SECRET"
  t "conf roundtrip path"   "/tmp/pp" "$REPO_PATH"
  if [ -n "$_oldcur" ]; then
    printf '%s' "$_oldcur" > "$DEPLOY_STATE_DIR/current"
  else
    rm -f "$DEPLOY_STATE_DIR/current"
  fi
  rm -f "$(conf_path_for_slug t)"
  rm -rf "$_tmp"

  echo
  if [ "$_fail" = "0" ]; then
    ok "selftest: ALL PASSED"
  else
    err "selftest: FAILURES DETECTED"
  fi
  return $_fail
}
