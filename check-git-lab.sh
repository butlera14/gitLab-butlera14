#!/usr/bin/env bash
set -euo pipefail

LAB="${1:-git-lab}"

fail() {
    printf 'NOT READY: %s\n' "$*" >&2
    printf 'Run: bash ./reset-git-lab.sh %q and try again.\n' "$LAB" >&2
    exit 1
}

ready() {
    printf 'PASS: %s\n' "$*"
}

require_repo() {
    local repo="$1"
    [[ -d "$repo/.git" ]] || fail "missing or invalid scenario: $(basename "$repo")"
}

require_clean() {
    local repo="$1"
    [[ -z "$(git -C "$repo" status --porcelain)" ]] || fail "$(basename "$repo") is not at its starting state"
}

require_branch() {
    local repo="$1" branch="$2"
    git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" || fail "$(basename "$repo") is missing required setup state"
}

require_head() {
    local repo="$1" branch="$2"
    [[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$branch" ]] || \
        fail "$(basename "$repo") is not on the expected starting branch"
}

command -v git >/dev/null 2>&1 || fail "Git is not available on PATH"

[[ -d "$LAB" ]] || fail "lab directory not found: $LAB"
for repo in 01-objects 02-staging 03-remotes-alice 03-remotes-bob 04-merge 05-rebase 06-interactive-rebase 07-conflict 08-reset-reflog 09-bisect; do
    require_repo "$LAB/$repo"
done
[[ -d "$LAB/03-origin.git" ]] || fail "remote scenario is incomplete"

# 01 -- repository/object scenario
require_clean "$LAB/01-objects"
require_branch "$LAB/01-objects" main
require_branch "$LAB/01-objects" feature/validation
require_head "$LAB/01-objects" main
[[ -z "$(git -C "$LAB/01-objects" remote)" ]] || fail "01-objects is not at its starting state"
git -C "$LAB/01-objects" merge-base main feature/validation >/dev/null || fail "01-objects has invalid branch ancestry"
ready "01-objects is ready"

# 02 -- intentionally dirty working tree, unchanged index
require_head "$LAB/02-staging" main
[[ -z "$(git -C "$LAB/02-staging" diff --cached --name-only)" ]] || fail "02-staging has already been staged"
[[ "$(git -C "$LAB/02-staging" diff -- config.properties | grep -c '^@@' || true)" == "3" ]] || fail "02-staging is not at its prepared starting state"
git -C "$LAB/02-staging" diff -- config.properties | grep -q '^+timeout=60$' || fail "02-staging is missing the timeout edit"
git -C "$LAB/02-staging" diff -- config.properties | grep -q '^+log.level=DEBUG$' || fail "02-staging is missing the logging edit"
git -C "$LAB/02-staging" diff -- config.properties | grep -q '^+max.connections=250$' || fail "02-staging is missing the connection-limit edit"
ready "02-staging is ready"

# 03 -- remote copies begin aligned
for repo in "$LAB/03-remotes-alice" "$LAB/03-remotes-bob"; do
    require_clean "$repo"
    require_branch "$repo" main
    require_head "$repo" main
    git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null || fail "remote scenario is incomplete"
    origin_url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
    [[ -n "$origin_url" && "$(basename "$origin_url")" == "03-origin.git" ]] || fail "$(basename "$repo") origin does not target the isolated lab remote"
    git -C "$repo" ls-remote --exit-code origin refs/heads/main >/dev/null 2>&1 || fail "$(basename "$repo") cannot reach the isolated lab remote"
done
alice_main="$(git -C "$LAB/03-remotes-alice" rev-parse main)"
alice_origin="$(git -C "$LAB/03-remotes-alice" rev-parse origin/main)"
bob_main="$(git -C "$LAB/03-remotes-bob" rev-parse main)"
bob_origin="$(git -C "$LAB/03-remotes-bob" rev-parse origin/main)"
remote_main="$(git --git-dir="$LAB/03-origin.git" rev-parse main)"
[[ "$(git --git-dir="$LAB/03-origin.git" rev-parse --is-bare-repository)" == "true" ]] || fail "03-origin.git is not a bare repository"
[[ "$(git --git-dir="$LAB/03-origin.git" for-each-ref --format='%(refname)' refs/heads | sort)" == "refs/heads/main" ]] || fail "03-origin.git exposes unexpected branches"
[[ -z "$(git --git-dir="$LAB/03-origin.git" for-each-ref --format='%(refname)' refs/tags)" ]] || fail "03-origin.git exposes unexpected tags"
[[ "$alice_main" == "$alice_origin" && "$alice_origin" == "$bob_main" && "$bob_main" == "$bob_origin" && "$bob_origin" == "$remote_main" ]] || fail "03-remotes has already been advanced"
ready "03-remotes is ready"

# 04 -- merge scenario
require_clean "$LAB/04-merge"
require_branch "$LAB/04-merge" main
require_branch "$LAB/04-merge" feature/validation
require_head "$LAB/04-merge" main
[[ "$(git -C "$LAB/04-merge" rev-list --count "$(git -C "$LAB/04-merge" merge-base main feature/validation)"..main)" == "2" ]] || fail "04-merge is not at its starting state"
[[ "$(git -C "$LAB/04-merge" rev-list --count "$(git -C "$LAB/04-merge" merge-base main feature/validation)"..feature/validation)" == "2" ]] || fail "04-merge is not at its starting state"
ready "04-merge is ready"

# 05 -- rebase scenario
require_clean "$LAB/05-rebase"
require_branch "$LAB/05-rebase" main
require_branch "$LAB/05-rebase" feature/validation
[[ "$(git -C "$LAB/05-rebase" symbolic-ref --short HEAD)" == "feature/validation" ]] || fail "05-rebase is not at its starting state"
[[ "$(git -C "$LAB/05-rebase" rev-list --count main..feature/validation)" == "2" ]] || fail "05-rebase is not at its starting state"
ready "05-rebase is ready"

# 06 -- interactive rebase scenario
require_clean "$LAB/06-interactive-rebase"
require_head "$LAB/06-interactive-rebase" feature/parser
[[ "$(git -C "$LAB/06-interactive-rebase" rev-list --count main..HEAD)" == "4" ]] || fail "06-interactive-rebase is not at its starting state"
(
    cd "$LAB/06-interactive-rebase"
    bash ./tests/test-parser.sh >/dev/null
) || fail "06-interactive-rebase setup test failed"
ready "06-interactive-rebase is ready"

# 07 -- conflict scenario, not yet merging
require_clean "$LAB/07-conflict"
require_branch "$LAB/07-conflict" main
require_branch "$LAB/07-conflict" feature/conflict
require_head "$LAB/07-conflict" main
[[ ! -e "$LAB/07-conflict/.git/MERGE_HEAD" ]] || fail "07-conflict already has an active merge"
[[ "$(git -C "$LAB/07-conflict" show "$(git -C "$LAB/07-conflict" merge-base main feature/conflict):config.properties" | grep '^timeout=')" == "timeout=30" ]] || fail "07-conflict has an invalid merge base"
[[ "$(git -C "$LAB/07-conflict" show main:config.properties | grep '^timeout=')" == "timeout=60" ]] || fail "07-conflict main is not prepared correctly"
[[ "$(git -C "$LAB/07-conflict" show feature/conflict:config.properties | grep '^timeout=')" == "timeout=DEFAULT_TIMEOUT" ]] || fail "07-conflict feature branch is not prepared correctly"
ready "07-conflict is ready"

# 08 -- recovery scenario, before reset
require_clean "$LAB/08-reset-reflog"
require_branch "$LAB/08-reset-reflog" main
require_head "$LAB/08-reset-reflog" main
git -C "$LAB/08-reset-reflog" rev-parse --verify --quiet F >/dev/null || fail "08-reset-reflog is missing tag F"
[[ "$(git -C "$LAB/08-reset-reflog" rev-list --count F..main)" == "3" ]] || fail "08-reset-reflog is not at its starting state"
[[ -f "$LAB/08-reset-reflog/RECOVERY.txt" ]] || fail "08-reset-reflog is not at its starting state"
if git -C "$LAB/08-reset-reflog" show-ref --verify --quiet refs/heads/rescue; then
    fail "08-reset-reflog has already been recovered"
fi
ready "08-reset-reflog is ready"

# 09 -- bisect scenario, before a bisect session
require_clean "$LAB/09-bisect"
require_head "$LAB/09-bisect" demo/bisect
[[ ! -e "$LAB/09-bisect/.git/BISECT_START" ]] || fail "09-bisect already has an active bisect session"
git -C "$LAB/09-bisect" rev-parse --verify --quiet bisect-good >/dev/null || fail "09-bisect is missing bisect-good"
git -C "$LAB/09-bisect" rev-parse --verify --quiet bisect-bad >/dev/null || fail "09-bisect is missing bisect-bad"
git -C "$LAB/09-bisect" merge-base --is-ancestor bisect-good bisect-bad || fail "09-bisect endpoints are not valid"
[[ "$(git -C "$LAB/09-bisect" rev-list --count bisect-good..bisect-bad)" == "10" ]] || fail "09-bisect history is not at its prepared starting state"
[[ "$(git -C "$LAB/09-bisect" rev-parse HEAD)" == "$(git -C "$LAB/09-bisect" rev-parse bisect-bad)" ]] || fail "09-bisect is not at the bad endpoint"
[[ -f "$LAB/09-bisect/tests/test-compute.sh" ]] || fail "09-bisect classifier is missing"
if (cd "$LAB/09-bisect" && bash ./tests/test-compute.sh >/dev/null 2>&1); then
    fail "09-bisect classifier does not classify the bad endpoint as bad"
fi
ready "09-bisect is ready"

printf '\nGit lab: READY\n'
printf 'All IA 01 scenarios are at their expected starting states.\n'
