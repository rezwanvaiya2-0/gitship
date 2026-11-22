# ============================================================================
#  cpanel.sh — cPanel integration via the `uapi` command-line client that
#  ships with every cPanel account (no root needed). We register the cloned
#  repo in cPanel -> Git Version Control so the user can manage it from the
#  familiar cPanel UI (history, branch switcher, Update from Remote).
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

# cpanel_register_repo PATH NAME -> sets UAPI_OUT ; returns 0 on success
cpanel_register_repo() {
  local _rc
  UAPI_OUT=$("$UAPI_BIN" VersionControl create \
      "repository_path=$1" "repository_name=$2" 2>&1)
  _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  # uapi prints JSON; an error reply contains a non-empty errors array
  if printf '%s' "$UAPI_OUT" | grep -q '"errors": *\["'; then return 1; fi
  return 0
}

# cpanel_remove_repo PATH -> best-effort removal from cPanel's managed list
cpanel_remove_repo() {
  local _rc
  UAPI_OUT=$("$UAPI_BIN" VersionControl delete \
      "repository_path=$1" 2>&1)
  _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  if printf '%s' "$UAPI_OUT" | grep -q '"errors": *\["'; then return 1; fi
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
