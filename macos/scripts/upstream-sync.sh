#!/usr/bin/env bash
# Take in upstream (rueblose/alive) updates and report what must be ported to Swift.
# See macos/docs/UPSTREAM.md.
#
#   upstream-sync.sh                 fetch, merge upstream/main (clean tree required), report
#   upstream-sync.sh --report-only   fetch and report only (no merge)      [used by CI]
#   upstream-sync.sh --since <sha>   report from <sha> instead of macos/UPSTREAM_SYNC
#   upstream-sync.sh --markdown      GitHub-flavoured markdown report
#   upstream-sync.sh --mark [sha]    record sha (default upstream/main) in macos/UPSTREAM_SYNC
set -euo pipefail

UPSTREAM_URL="https://github.com/rueblose/alive.git"
UPSTREAM_REF="upstream/main"
SYNC_REL="macos/UPSTREAM_SYNC"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(git -C "$MACOS_DIR" rev-parse --show-toplevel)"
MAP_FILE="$MACOS_DIR/upstream-map.tsv"
SYNC_FILE="$MACOS_DIR/UPSTREAM_SYNC"
TAB="$(printf '\t')"

REPORT_ONLY=0
MARKDOWN=0
MARK=0
MARK_SHA=""
SINCE=""

usage() {
  sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --report-only) REPORT_ONLY=1 ;;
    --markdown) MARKDOWN=1 ;;
    --since)
      [ $# -ge 2 ] || die "--since needs a commit sha"
      SINCE="$2"; shift ;;
    --mark)
      MARK=1
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then MARK_SHA="$2"; shift; fi ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

git_() { git -C "$REPO_ROOT" "$@"; }

fetch_upstream() {
  if ! git_ remote get-url upstream >/dev/null 2>&1; then
    git_ remote add upstream "$UPSTREAM_URL"
  fi
  git_ fetch --quiet --tags upstream
}

# --- --mark ---------------------------------------------------------------
if [ "$MARK" -eq 1 ]; then
  fetch_upstream
  target="${MARK_SHA:-$UPSTREAM_REF}"
  sha="$(git_ rev-parse --verify --quiet "$target^{commit}")" || die "cannot resolve '$target'"
  printf '%s\n' "$sha" > "$SYNC_FILE"
  echo "Recorded $sha in $SYNC_REL"
  echo "Commit it, e.g.:  git add $SYNC_REL && git commit -m 'chore(mac): mark upstream $(git_ rev-parse --short "$sha") as ported'"
  exit 0
fi

# --- fetch / merge --------------------------------------------------------
fetch_upstream

if [ "$REPORT_ONLY" -eq 0 ]; then
  if [ -n "$(git_ status --porcelain --untracked-files=no)" ]; then
    die "working tree has uncommitted changes; commit or stash them first (or use --report-only)"
  fi
  branch="$(git_ rev-parse --abbrev-ref HEAD)"
  if git_ merge-base --is-ancestor "$UPSTREAM_REF" HEAD 2>/dev/null; then
    echo "Nothing to merge: $UPSTREAM_REF is already in $branch."
  else
    echo "Merging $UPSTREAM_REF into $branch ..."
    if ! git_ merge --no-edit "$UPSTREAM_REF"; then
      git_ merge --abort >/dev/null 2>&1 || true
      cat >&2 <<MSG

The merge conflicted and was aborted (your branch is unchanged).
The Swift port must never edit upstream-owned files (see macos/docs/PORTING.md, rule 2.1),
so a conflict means an upstream file was modified on this branch. Find it with:
  git diff --name-only $UPSTREAM_REF...HEAD -- . ':!macos' ':!.github'
Restore those files to upstream's version (or move the change under macos/) and re-run.
MSG
      exit 1
    fi
  fi
fi

# --- report ---------------------------------------------------------------
if [ -z "$SINCE" ]; then
  [ -f "$SYNC_FILE" ] || die "$SYNC_REL not found; use --since <sha>"
  SINCE="$(tr -d '[:space:]' < "$SYNC_FILE")"
fi
since_sha="$(git_ rev-parse --verify --quiet "$SINCE^{commit}")" \
  || die "'$SINCE' is not a known commit (try: git fetch upstream)"
head_sha="$(git_ rev-parse --verify --quiet "$UPSTREAM_REF^{commit}")" \
  || die "cannot resolve $UPSTREAM_REF"
short() { git_ rev-parse --short "$1"; }

count="$(git_ rev-list --count "$since_sha..$head_sha")"
if [ "$count" -eq 0 ]; then
  echo "Up to date with upstream ($(short "$head_sha"))"
  exit 0
fi
[ -f "$MAP_FILE" ] || die "$MAP_FILE not found"

# lookup <path>: prints "STATUS<TAB>swift_paths<TAB>owner<TAB>notes".
# STATUS: MAPPED | NOPORT | UNMAPPED. An exact row wins; otherwise the longest
# directory row (key ending in "/") that is a prefix of the path.
lookup() {
  awk -F'\t' -v p="$1" '
    /^#/ || $1 == "" { next }
    {
      key = $1
      if (key == p) { ex = 1; es = $2; eo = $3; en = $4; next }
      if (substr(key, length(key)) == "/" && index(p, key) == 1 && length(key) > plen) {
        plen = length(key); ds = $2; dobj = $3; dn = $4; dir = 1
      }
    }
    END {
      if (ex)       { s = es; o = eo; n = en }
      else if (dir) { s = ds; o = dobj; n = dn }
      else          { print "UNMAPPED\t\t\t"; exit }
      st = (s == "-" || s == "") ? "NOPORT" : "MAPPED"
      print st "\t" s "\t" o "\t" n
    }' "$MAP_FILE"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/upstream-sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/checklist"
: > "$TMP/unmapped"

if [ "$MARKDOWN" -eq 1 ]; then
  printf '## Upstream: %s unported commit(s)\n\n' "$count"
  printf 'Range `%s..%s` of `rueblose/alive`. Procedure: `macos/docs/UPSTREAM.md`.\n\n' "$(short "$since_sha")" "$(short "$head_sha")"
else
  printf 'Upstream: %s unported commit(s), %s..%s\n' "$count" "$(short "$since_sha")" "$(short "$head_sha")"
  printf '======================================================================\n'
fi

# Swift paths in the map are relative to macos/; "../x" means repo-root x.
repo_path() {
  case "$1" in
    ../*) printf '%s' "${1#../}" ;;
    *) printf 'macos/%s' "$1" ;;
  esac
}

print_file() { # status path kind swift owner notes
  local st="$1" path="$2" kind="$3" swift="$4" owner="$5" notes="$6" target
  target="$(printf '%s' "$swift" | sed 's/;/, /g')"
  if [ "$MARKDOWN" -eq 1 ]; then
    case "$kind" in
      MAPPED) printf -- '- `%s` `%s` -> `%s` (owner %s)%s\n' "$st" "$path" "$target" "$owner" "${notes:+ - $notes}" ;;
      NOPORT) printf -- '- `%s` `%s` -> no port needed (%s)\n' "$st" "$path" "${notes:-no reason given}" ;;
      *)      printf -- '- `%s` `%s` -> **UNMAPPED — add a row to upstream-map.tsv**\n' "$st" "$path" ;;
    esac
  else
    case "$kind" in
      MAPPED) printf '  %s %s\n      -> %s  [owner %s]%s\n' "$st" "$path" "$target" "$owner" "${notes:+  ($notes)}" ;;
      NOPORT) printf '  %s %s\n      -> no port needed (%s)\n' "$st" "$path" "${notes:-no reason given}" ;;
      *)      printf '  %s %s\n      -> UNMAPPED — add a row to upstream-map.tsv\n' "$st" "$path" ;;
    esac
  fi
}

git_ log --reverse --format="%h%x09%ad%x09%s" --date=short "$since_sha..$head_sha" > "$TMP/commits"

while IFS="$TAB" read -r sha date subject; do
  if [ "$MARKDOWN" -eq 1 ]; then
    printf '### `%s` %s %s\n\n' "$sha" "$date" "$subject"
  else
    printf '\n%s  %s  %s\n' "$sha" "$date" "$subject"
  fi
  git_ show --no-renames --name-status --format= "$sha" | sort -t "$TAB" -k2 > "$TMP/files"
  if [ ! -s "$TMP/files" ]; then
    if [ "$MARKDOWN" -eq 1 ]; then echo "_(no file changes)_"; else echo "  (no file changes)"; fi
  fi
  while IFS="$TAB" read -r st path; do
    [ -n "$path" ] || continue
    IFS="$TAB" read -r kind swift owner notes <<EOT
$(lookup "$path")
EOT
    case "$kind" in
      MAPPED) printf '%s\t%s\n' "$swift" "$owner" >> "$TMP/checklist" ;;
      UNMAPPED) printf '%s\n' "$path" >> "$TMP/unmapped" ;;
    esac
    print_file "$st" "$path" "$kind" "$swift" "$owner" "$notes"
  done < "$TMP/files"
  if [ "$MARKDOWN" -eq 1 ]; then echo; fi
done < "$TMP/commits"

# Deduplicated checklist: split multi-path rows and pair each path with its owner.
awk -F'\t' '
  { np = split($1, ps, ";"); no = split($2, os, ";")
    for (i = 1; i <= np; i++) { o = (no == np) ? os[i] : $2; print ps[i] "\t" o } }' "$TMP/checklist" \
  | sort -u > "$TMP/swift"
sort -u "$TMP/unmapped" > "$TMP/unmapped.u"

if [ "$MARKDOWN" -eq 1 ]; then
  echo "### Swift files to update"
  echo
  if [ -s "$TMP/swift" ]; then
    while IFS="$TAB" read -r f o; do printf -- '- [ ] `%s` (%s)\n' "$(repo_path "$f")" "$o"; done < "$TMP/swift"
  else
    echo "_None: only files that need no port changed._"
  fi
  if [ -s "$TMP/unmapped.u" ]; then
    printf '\n### Unmapped upstream files\n\n'
    while IFS= read -r f; do printf -- '- [ ] `%s`: add a row to `macos/upstream-map.tsv`\n' "$f"; done < "$TMP/unmapped.u"
  fi
  printf '\nAfter porting and `swift test`, run `macos/scripts/upstream-sync.sh --mark` and commit `%s`.\n' "$SYNC_REL"
else
  printf '\nSwift files to update\n---------------------\n'
  if [ -s "$TMP/swift" ]; then
    while IFS="$TAB" read -r f o; do printf '  [ ] %s  (%s)\n' "$(repo_path "$f")" "$o"; done < "$TMP/swift"
  else
    echo "  (none: only files that need no port changed)"
  fi
  if [ -s "$TMP/unmapped.u" ]; then
    printf '\nUnmapped upstream files\n-----------------------\n'
    sed 's/^/  ! /' "$TMP/unmapped.u"
  fi
  printf '\nWhen done: run swift test, then  macos/scripts/upstream-sync.sh --mark  and commit %s\n' "$SYNC_REL"
fi
exit 0
