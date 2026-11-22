# ============================================================================
#  ui.sh — colors, messaging, prompts (kept ASCII-safe + bash 3.2 compatible
#  so it behaves the same on old cPanel shells and macOS)
# ============================================================================

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_OK=$'\033[32m';   C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
  C_INFO=$'\033[36m'; C_TITLE=$'\033[1;36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_TITLE=""
fi

ok()   { printf '%s[ok]%s %s\n'   "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s[!!]%s %s\n'   "$C_WARN" "$C_RESET" "$*"; }
err()  { printf '%s[xx]%s %s\n'   "$C_ERR"  "$C_RESET" "$*" >&2; }
info() { printf '%s  - %s%s\n'    "$C_INFO" "$*" "$C_RESET"; }
dim()  { printf '%s    %s%s\n'    "$C_DIM"  "$*" "$C_RESET"; }
step() { printf '\n%s== %s ==%s\n' "$C_TITLE" "$*" "$C_RESET"; }
hr()   { printf '%s%s%s\n' "$C_DIM" "--------------------------------------------------------------" "$C_RESET"; }

die() {
  err "$@"
  printf '\n%sCheck %srepo status%s for details, or re-run this command.\n' \
    "$C_DIM" "$C_BOLD" "$C_RESET" >&2
  exit 1
}

banner() {
  printf '\n%s' "$C_TITLE"
  cat <<'BANNER'
  +--------------------------------------------------------+
  |  repo  --  private GitHub repos on cPanel, made easy   |
  |  setup + connection checks + cPanel native, no root    |
  +--------------------------------------------------------+
BANNER
  printf '%s\n' "$C_RESET"
}

# ask VARNAME "Question" [default]
ask() {
  local _var="$1" _q="$2" _def="${3:-}" _ans=""
  if [ -n "$_def" ]; then
    printf '%s? %s %s[%s]%s: ' "$C_INFO" "$_q" "$C_DIM" "$_def" "$C_RESET" >&2
  else
    printf '%s? %s%s: ' "$C_INFO" "$_q" "$C_RESET" >&2
  fi
  read -r _ans
  if [ -z "$_ans" ] && [ -n "$_def" ]; then _ans="$_def"; fi
  eval "$_var=\"\$_ans\""
}

# ask_secret VARNAME "Question"  (input hidden)
ask_secret() {
  local _var="$1" _q="$2" _ans=""
  printf '%s? %s %s(input hidden)%s: ' "$C_INFO" "$_q" "$C_DIM" "$C_RESET" >&2
  read -rs _ans
  printf '\n' >&2
  eval "$_var=\"\$_ans\""
}

# confirm "Question" [y|n] -> returns 0 when answered yes
confirm() {
  local _q="$1" _def="${2:-y}" _ans=""
  if [ "$_def" = "y" ]; then
    printf '%s? %s %s[Y/n]%s: ' "$C_INFO" "$_q" "$C_DIM" "$C_RESET" >&2
  else
    printf '%s? %s %s[y/N]%s: ' "$C_INFO" "$_q" "$C_DIM" "$C_RESET" >&2
  fi
  read -r _ans
  [ -z "$_ans" ] && _ans="$_def"
  case "$_ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# print_row "Label" "value" — aligned summary card row
print_row() {
  printf '%s%-16s%s %s\n' "$C_DIM" "$1:" "$C_RESET" "$2"
}
