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
