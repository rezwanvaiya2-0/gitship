# ============================================================================
#  github.sh — GitHub API helpers (curl + sed/grep only; no jq dependency,
#  because shared hosts rarely have it). Token is kept in GIT_TOKEN in memory
#  only and is never written to disk by this tool.
# ============================================================================

GH_API_BASE="https://api.github.com"
GIT_TOKEN=""

# gh_api METHOD PATH [JSON_BODY]  -> sets GH_STATUS (http code), GH_BODY
gh_api() {
  local _method="$1" _path="$2" _body="${3:-}" _raw _rc
  local _args=(-sS -X "$_method"
               -H "Accept: application/vnd.github+json"
               -H "X-GitHub-Api-Version: 2022-11-28")
  [ -n "$GIT_TOKEN" ] && _args+=(-H "Authorization: Bearer $GIT_TOKEN")
  [ -n "$_body" ]     && _args+=(-H "Content-Type: application/json" -d "$_body")

  _raw=$(curl "${_args[@]}" -w '\n%{http_code}' "$GH_API_BASE$_path" 2>/dev/null)
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    GH_STATUS="000"
    GH_BODY="network error: could not reach $GH_API_BASE"
    return 1
  fi
  GH_STATUS=$(printf '%s\n' "$_raw" | tail -n 1)
  GH_BODY=$(printf '%s\n' "$_raw" | sed '$d')
  return 0
}

# json_str VALUE -> prints VALUE as a JSON string literal
json_str() {
  local _e
  _e=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '"%s"' "$_e"
}

# parse_owner_repo URL -> sets OWNER, REPO ; returns 1 when unrecognized.
# Accepts: git@github.com:o/r.git | ssh://git@github.com/o/r.git
#          https://github.com/o/r(.git)(/) | o/r
parse_owner_repo() {
  local _u _path
  _u=$(printf '%s' "$1" | tr -d '[:space:]' | sed 's:/*$::; s/\.git$//')
  OWNER=""; REPO=""
  case "$_u" in
    *github.com:*)  _path="${_u#*github.com:}" ;;
    *github.com/*)  _path="${_u#*github.com/}" ;;
    [A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*)  _path="$_u" ;;
    *) return 1 ;;
  esac
  case "$_path" in
    */*) OWNER="${_path%%/*}"; REPO="${_path#*/}" ;;
    *)   return 1 ;;
  esac
  case "$REPO" in */*) return 1 ;; esac
  [ -z "$OWNER" ] && return 1
  [ -z "$REPO"  ] && return 1
  return 0
}

# slugify TEXT -> lowercase, a-z0-9 and single dashes only
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9-' '-' \
    | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
}

# gen_hex N_BYTES -> 2N random hex chars (portable; no openssl required)
gen_hex() {
  local _n="${1:-16}"
  od -An -N"$_n" -tx1 /dev/urandom | tr -d ' \n'
}

# parse_ssh_keys_from_json -> prints public key strings one per line.
# Expects GH_BODY to contain GitHub /meta style JSON. (Split out for testing.)
parse_ssh_keys_from_json() {
  printf '%s\n' "$GH_BODY" \
    | sed -n 's/.*"\([a-z0-9-]\{3,\} [A-Za-z0-9+/=]\{40,\}\)".*/\1/p' \
    | sort -u
}

# gh_meta_ssh_keys -> fetches github.com's SSH host keys via the API
gh_meta_ssh_keys() {
  gh_api GET "/meta" || return 1
  [ "$GH_STATUS" = "200" ] || return 1
  parse_ssh_keys_from_json
}

# verify_repo_access OWNER REPO -> friendly pass/fail; sets GH_DEFAULT_BRANCH
verify_repo_access() {
  gh_api GET "/repos/$1/$2" \
    || die "Cannot reach api.github.com from this server. Check network/firewall."
  case "$GH_STATUS" in
    200)
      GH_DEFAULT_BRANCH=$(printf '%s' "$GH_BODY" \
        | grep -o '"default_branch": *"[^"]*"' | head -n 1 \
        | sed 's/.*: *"//; s/"$//')
      [ -n "$GH_DEFAULT_BRANCH" ] || GH_DEFAULT_BRANCH="main"
      return 0
      ;;
    401)
      die "GitHub says the token is invalid or expired (401).
Create a fresh token: https://github.com/settings/personal-access-tokens/new
and run this command again."
      ;;
    404)
      die "The token is OK, but repo '$1/$2' is NOT accessible (404).
Either the repo does not exist, or your token does not include it.
Fine-grained tokens: under 'Repository access' select this repo."
      ;;
    *)
      die "Unexpected GitHub API status $GH_STATUS while checking $1/$2.
Response: $(printf '%s' "$GH_BODY" | head -c 300)"
      ;;
  esac
}

# add_deploy_key OWNER REPO PUBKEY TITLE
# returns 0 when the key is (or already was) a deploy key of the repo.
add_deploy_key() {
  local _owner="$1" _repo="$2" _pub="$3" _title="$4" _rc
  gh_api POST "/repos/$_owner/$_repo/keys" \
    "$(printf '{"title":%s,"key":%s,"read_only":true}' \
        "$(json_str "$_title")" "$(json_str "$_pub")")"
  _rc=$?
  [ "$_rc" -eq 0 ] || die "Network error while adding the deploy key."
  case "$GH_STATUS" in
    201) return 0 ;;
    422)
      # Could be "already in use". If it is already THIS repo's key, that's fine.
      gh_api GET "/repos/$_owner/$_repo/keys" || return 2
      if printf '%s' "$GH_BODY" | grep -qF "$_pub"; then
        return 0
      fi
      err "GitHub rejected this key: it is already used elsewhere
(another repo's deploy key, or an account SSH key)."
      return 2
      ;;
    403)
      die "The token may read the repo but cannot manage deploy keys (403).
Fine-grained tokens need:  Administration -> Read and write"
      ;;
    401)
      die "GitHub rejected the token (401) while adding the deploy key."
      ;;
    *)
      die "Unexpected GitHub API status $GH_STATUS while adding the deploy key.
Response: $(printf '%s' "$GH_BODY" | head -c 300)"
      ;;
  esac
}
