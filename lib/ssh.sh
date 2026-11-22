# ============================================================================
#  ssh.sh — SSH deploy key management: key generation, ssh config blocks,
#  known_hosts pre-seeding (kills the interactive trust prompt) and the
#  GitHub auth test. Everything happens inside $HOME — no root anywhere.
# ============================================================================

ensure_ssh_dir() {
  [ -d "$HOME/.ssh" ] || mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" 2>/dev/null
}

# seed_known_hosts — pre-trust github.com using GitHub's official host keys
# from the API, so neither git nor cPanel ever asks a scary yes/no question.
seed_known_hosts() {
  ensure_ssh_dir
  local _kh="$HOME/.ssh/known_hosts"
  [ -f "$_kh" ] || : > "$_kh"
  chmod 600 "$_kh" 2>/dev/null
  if grep -q 'github.com ssh-' "$_kh" 2>/dev/null || grep -q 'github.com ecdsa-' "$_kh" 2>/dev/null; then
    ok "github.com is already trusted in known_hosts"
    return 0
  fi
  info "Fetching GitHub's official SSH host keys to pre-trust github.com..."
  local _keys
  _keys=$(gh_meta_ssh_keys)
  if [ -z "$_keys" ]; then
    warn "Could not fetch GitHub host keys (network hiccup?)."
    warn "If a trust prompt appears later, answer 'yes' — or re-run this tool."
    return 1
  fi
  printf '%s\n' "$_keys" | while IFS= read -r _k; do
    [ -n "$_k" ] && printf 'github.com %s\n' "$_k" >> "$_kh"
  done
  if grep -q 'github.com ' "$_kh"; then
    ok "github.com host key pre-trusted (no interactive prompts will appear)"
    return 0
  fi
  return 1
}

# gen_deploy_key KEYPATH — creates KEYPATH and KEYPATH.pub (ed25519, RSA fallback)
gen_deploy_key() {
  local _path="$1"
  if [ -f "$_path" ] && [ -f "$_path.pub" ]; then
    ok "SSH key already exists: $_path (reusing it)"
    KEY_ALG="existing"
    return 0
  fi
  ensure_ssh_dir
  if ssh-keygen -t ed25519 -f "$_path" -N '' \
       -C "cpanel-deploy-$(date +%Y%m%d%H%M%S)" >/dev/null 2>&1; then
    KEY_ALG="ed25519"
  else
    info "This server's ssh-keygen lacks ed25519; generating RSA-4096 instead..."
    ssh-keygen -t rsa -b 4096 -f "$_path" -N '' \
      -C "cpanel-deploy-$(date +%Y%m%d%H%M%S)" >/dev/null 2>&1 \
      || die "ssh-keygen failed on this server — please report this to the tool author."
    KEY_ALG="rsa"
  fi
  chmod 600 "$_path" 2>/dev/null
  chmod 644 "$_path.pub" 2>/dev/null
  ok "SSH deploy key generated ($KEY_ALG): $_path"
}

# write_ssh_config_block ALIAS KEYPATH SLUG — idempotent Host block
write_ssh_config_block() {
  ensure_ssh_dir
  local _cfg="$HOME/.ssh/config" _alias="$1" _keypath="$2" _slug="$3"
  [ -f "$_cfg" ] || : > "$_cfg"
  chmod 600 "$_cfg" 2>/dev/null
  if grep -q "# cpanel-deploy:begin $_slug" "$_cfg" 2>/dev/null; then
    ok "SSH config block for '$_slug' already present"
    return 0
  fi
  {
    printf '\n# cpanel-deploy:begin %s\n' "$_slug"
    printf 'Host %s\n' "$_alias"
    printf '    HostName github.com\n'
    printf '    User git\n'
    printf '    IdentityFile %s\n' "$_keypath"
    printf '    IdentitiesOnly yes\n'
    printf '# cpanel-deploy:end %s\n' "$_slug"
  } >> "$_cfg"
  ok "SSH config updated (Host alias: $_alias)"
}

# remove_ssh_config_block SLUG — deletes our managed block
remove_ssh_config_block() {
  local _cfg="$HOME/.ssh/config"
  [ -f "$_cfg" ] || return 0
  sed -i.bak "/# cpanel-deploy:begin $1/,/# cpanel-deploy:end $1/d" "$_cfg" \
    && rm -f "$_cfg.bak"
}

# ssh_auth_test HOST-ALIAS -> returns 0 when GitHub accepts our deploy key.
# NOTE: `ssh -T git@github.com` exits 1 ON SUCCESS ("...successfully
# authenticated"), so we detect success by output text, not exit code.
ssh_auth_test() {
  local _out _rc
  _out=$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 \
              -o StrictHostKeyChecking=no "git@$1" 2>&1)
  _rc=$?
  SSH_TEST_OUT="$_out"
  if [ "$_rc" -eq 1 ] && printf '%s' "$_out" | grep -q 'successfully authenticated'; then
    return 0
  fi
  return 1
}
