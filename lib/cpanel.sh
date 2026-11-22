# ============================================================================
#  cpanel.sh — cPanel integration via the `uapi` command-line client that
#  ships with every cPanel account (no root needed). We register the cloned
#  repo in cPanel -> Git Version Control so the user can manage it from the
#  familiar cPanel UI (history, branch switcher, Update from Remote).
#
#  Verified against the official OpenAPI spec:
#    VersionControl::create requires:  type=git  name=<display name>
#                                      repository_root=<absolute path>
#    (omitting source_repository makes cPanel adopt an existing repo dir)
#    uapi CLI JSON uses spaced style:  "errors" : [ ... ]  /  "status" : 1
# ============================================================================

UAPI_BIN=""

detect_uapi() {
  if command -v uapi >/dev/null 2>&1; then
    UAPI_BIN="uapi"
  elif [ -x "/usr/local/cpanel/bin/uapi" ]; then
    UAPI_BIN="/usr/local/cpanel/bin/uapi"
  else
    return 1
  fi
  return 0
}

# uapi_output_failed OUTPUT — returns 0 when uapi's JSON reports failure.
# Handles both compact ("errors":["x"]) and spaced ("errors" : ["x"]) styles.
uapi_output_failed() {
  printf '%s' "$1" | grep -Eq '"errors"[ ]*:[ ]*\["' && return 0
  printf '%s' "$1" | grep -Eq '"status"[ ]*:[ ]*0'   && return 0
  return 1
}

# cpanel_verify_registered PATH — returns 0 when cPanel's repo list has PATH
cpanel_verify_registered() {
  local _out
  _out=$("$UAPI_BIN" VersionControl retrieve 2>&1) || return 1
  UAPI_LIST="$_out"
  printf '%s' "$_out" | grep -qF "$1"
}

# cpanel_register_repo ROOT NAME — create + verify. Sets UAPI_OUT / UAPI_LIST.
cpanel_register_repo() {
  local _rc
  UAPI_OUT=$("$UAPI_BIN" VersionControl create \
      "type=git" "name=$2" "repository_root=$1" 2>&1)
  _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  if uapi_output_failed "$UAPI_OUT"; then return 1; fi
  # Don't trust the reply alone — confirm cPanel now actually lists the repo.
  cpanel_verify_registered "$1"
}

# cpanel_remove_repo ROOT NAME — best-effort removal from cPanel's list
cpanel_remove_repo() {
  local _rc
  UAPI_OUT=$("$UAPI_BIN" VersionControl delete \
      "repository_root=$1" "name=$2" 2>&1)
  _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  if uapi_output_failed "$UAPI_OUT"; then return 1; fi
  if cpanel_verify_registered "$1"; then return 1; fi
  return 0
}

# detect_main_domain -> best-effort primary domain of this cPanel account
detect_main_domain() {
  detect_uapi || return 1
  local _out
  _out=$("$UAPI_BIN" DomainInfo domains 2>/dev/null) || return 1
  printf '%s' "$_out" \
    | grep -o '"main_domain": *"[^"]*"' | head -n 1 \
    | sed 's/.*: *"//; s/"$//'
}

# ============================================================================
#  SSH key visibility in cPanel -> SSH Access -> Manage SSH Keys
#
#  The modern UAPI has no key-management functions; cPanel's official docs
#  point to cPanel API 2: SSH::genkey (create through cPanel so the key is
#  natively managed + listed) and SSH::importkey (register an existing key's
#  contents). Both are callable from Terminal via the shipped `cpapi2` CLI.
# ============================================================================

CPAPI2_BIN=""

detect_cpapi2() {
  if command -v cpapi2 >/dev/null 2>&1; then
    CPAPI2_BIN="cpapi2"
  elif [ -x "/usr/local/cpanel/bin/cpapi2" ]; then
    CPAPI2_BIN="/usr/local/cpanel/bin/cpapi2"
  else
    return 1
  fi
  return 0
}

# cpapi2_call MODULE FUNC PARAMS... -> sets API2_OUT
cpapi2_call() {
  local _m="$1" _f="$2" _u
  shift 2
  _u=$(whoami 2>/dev/null || printf '%s' "${USER:-root}")
  API2_OUT=$("$CPAPI2_BIN" --user="$_u" "$_m" "$_f" "$@" 2>&1)
}

# api2_failed OUTPUT — 0 when the API2 JSON reports result: 0
api2_failed() {
  printf '%s' "$1" | grep -Eq '"result"[ ]*:[ ]*0' && return 0
  return 1
}

# uri_encode VALUE — URI-encode (cpapi2 CLI requires it); perl first, pure-od fallback
uri_encode() {
  perl -MURI::Escape -e 'print uri_escape($ARGV[0])' "$1" 2>/dev/null && return 0
  printf '%s' "$1" | od -An -tx1 | tr ' ' '\n' | grep -v '^$' \
    | sed 's/^/%/' | tr -d '\n'
}

# cpanel_genkey NAME — create ~/.ssh/NAME(.pub) THROUGH cPanel (rsa-4096),
# so the key pair is natively listed in cPanel -> SSH Access -> Manage SSH Keys.
cpanel_genkey() {
  local _name="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "[dry-run] $CPAPI2_BIN SSH genkey bits=4096 name=$_name type=rsa"
    return 0
  fi
  ensure_ssh_dir
  cpapi2_call SSH genkey "bits=4096" "name=$_name" "type=rsa" || return 1
  if api2_failed "$API2_OUT"; then return 1; fi
  # trust but verify: the key files must actually exist now
  [ -f "$HOME/.ssh/$_name" ] && [ -f "$HOME/.ssh/$_name.pub" ]
}

# cpanel_key_visible NAME — 0 when cPanel's key system lists NAME
cpanel_key_visible() {
  local _name="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "[dry-run] verify key listing for $_name"
    return 0
  fi
  cpapi2_call SSH listkeys "keys=$_name" || return 1
  if api2_failed "$API2_OUT"; then return 1; fi
  printf '%s' "$API2_OUT" | grep -qF "$_name"
}

# cpanel_import_public_key NAME PUBFILE — register an existing PUBLIC key's
# contents under NAME so it shows in cPanel's key list. Uses a DISTINCT name:
# importkey overwrites same-named keys, so never pass the private key's name.
cpanel_import_public_key() {
  local _name="$1" _pubfile="$2" _enc
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "[dry-run] $CPAPI2_BIN SSH importkey (public half, name=$_name)"
    return 0
  fi
  ensure_ssh_dir
  _enc=$(uri_encode "$(cat "$_pubfile")") || return 1
  [ -n "$_enc" ] || return 1
  cpapi2_call SSH importkey "key=$_enc" "name=$_name" || return 1
  if api2_failed "$API2_OUT"; then return 1; fi
  cpanel_key_visible "$_name"
}
