#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-git-lab}"
START_DIR="$(pwd)"

if (( $# > 1 )); then
    printf 'Usage: bash ./build-git-lab.sh [LAB_DIRECTORY]\n' >&2
    exit 2
fi

# The build is intentionally destructive when the target already exists.
# Restrict it to one simple child-directory name so a typo cannot turn the
# reset operation into a recursive deletion elsewhere on the filesystem.
if [[ ! "$ROOT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    printf 'ERROR: unsafe lab directory name: %s\n' "$ROOT" >&2
    printf 'Use a simple directory name such as: git-lab\n' >&2
    exit 2
fi

for cmd in git sed grep; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'ERROR: required command not found: %s\n' "$cmd" >&2
        exit 1
    }
done

if [[ -e "$ROOT" || -L "$ROOT" ]]; then
    echo "Removing existing lab: $ROOT"
    rm -rf -- "$ROOT"
fi

mkdir -p -- "$ROOT"
cd -- "$ROOT"
ROOT_ABS="$(pwd)"

say() {
    printf '\n==> %s\n' "$*"
}

configure_repo() {
    git config user.name "Git Lab"
    git config user.email "git-lab@example.com"
    git config commit.gpgsign false
    git config advice.detachedHead false
    git config core.autocrlf false
    git config core.eol lf
    git config core.safecrlf false
}

strip_tags() {
    local tag
    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        git tag -d "$tag" >/dev/null
    done < <(git tag -l)
}

strip_bare_tags() {
    local gitdir="$1"
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        git --git-dir="$gitdir" update-ref -d "$ref"
    done < <(git --git-dir="$gitdir" for-each-ref --format='%(refname)' refs/tags)
}

clone_from_seed() {
    local name="$1"
    git -c core.autocrlf=false clone -q "$ROOT_ABS/seed.git" "$ROOT_ABS/$name"
    (
        cd "$ROOT_ABS/$name"
        configure_repo
        git checkout -q main
    )
}

make_local_scenario() {
    local name="$1"
    clone_from_seed "$name"
    (
        cd "$ROOT_ABS/$name"
        git remote remove origin
    )
}

say "Creating canonical teaching history"
mkdir base
cd base
git init -q
git symbolic-ref HEAD refs/heads/main
configure_repo

cat > .gitattributes <<'TXT'
.gitattributes text eol=lf
*.sh text eol=lf
*.properties text eol=lf
*.md text eol=lf
*.txt text eol=lf
TXT

cat > README.md <<'TXT'
# Git Lab

A tiny project used to explore Git.

## Purpose

This repository is intentionally small so that its complete history can be
read, changed, broken, and recovered during a lecture.
TXT

mkdir -p src tests
cat > tests/README.md <<'TXT'
# Tests

Small executable checks for the teaching project live here.
TXT

git add .gitattributes README.md tests/README.md
git commit -q -m "Initialize project"
git tag A

cat > config.properties <<'TXT'
# Core runtime settings
timeout=30
retry.count=3
retry.delay.ms=250

# Network settings
server.host=localhost
server.port=8080
connection.keepalive=true
connection.pool.size=10

# Logging settings
log.level=INFO
log.console=true
log.timestamps=true
log.file=app.log

# Feature switches
feature.validation=true
feature.metrics=false
feature.experimental=false

# Limits
max.connections=100
max.payload.kb=512
max.queue.depth=25
TXT

cat > src/config.sh <<'TXT'
#!/usr/bin/env bash

get_config() {
    local key="$1"
    grep "^${key}=" config.properties | cut -d= -f2-
}
TXT
chmod +x src/config.sh

git add config.properties src/config.sh
git commit -q -m "Add configuration loader"
git tag B

git checkout -q -b feature/validation
cat >> src/config.sh <<'TXT'

valid_timeout() {
    local timeout="$1"

    if [[ "$timeout" -le 0 ]]; then
        return 1
    fi

    return 0
}
TXT

git add src/config.sh
git commit -q -m "Add timeout validation"
git tag C

cat > tests/test-timeout.sh <<'TXT'
#!/usr/bin/env bash
set -euo pipefail

source src/config.sh

valid_timeout 30
! valid_timeout 0
! valid_timeout -1

echo "timeout tests passed"
TXT
chmod +x tests/test-timeout.sh

git add tests/test-timeout.sh
git commit -q -m "Add validation tests"
git tag D

git checkout -q main
cat > src/log.sh <<'TXT'
#!/usr/bin/env bash

log_message() {
    printf '[git-lab] %s\n' "$1"
}
TXT
chmod +x src/log.sh

git add src/log.sh
git commit -q -m "Add logging"
git tag E

cat >> README.md <<'TXT'

## Configuration

Application settings are stored in `config.properties`.

## Logging

Logging utilities are stored in `src/log.sh`.
TXT

git add README.md
git commit -q -m "Update README"
git tag F

cd "$ROOT_ABS"

# Immutable source for scenarios. Classroom pushes never target this remote.
say "Creating immutable seed repository"
git clone -q --bare base seed.git
git --git-dir=seed.git symbolic-ref HEAD refs/heads/main

# -----------------------------------------------------------------------------
# Lecture 01B scenarios
# -----------------------------------------------------------------------------
say "Preparing 01-objects"
clone_from_seed 01-objects
(
    cd 01-objects
    git branch feature/validation origin/feature/validation
    git remote remove origin
    strip_tags
)

say "Preparing 02-staging"
make_local_scenario 02-staging
(
    cd 02-staging
    strip_tags
    sed -i.bak 's/^timeout=30$/timeout=60/' config.properties
    sed -i.bak 's/^log.level=INFO$/log.level=DEBUG/' config.properties
    sed -i.bak 's/^max.connections=100$/max.connections=250/' config.properties
    rm -f config.properties.bak
)

say "Preparing isolated remote scenario"
git clone -q --bare seed.git 03-origin.git
git --git-dir=03-origin.git symbolic-ref HEAD refs/heads/main
git --git-dir=03-origin.git update-ref -d refs/heads/feature/validation
strip_bare_tags "$ROOT_ABS/03-origin.git"

git -c core.autocrlf=false clone -q "$ROOT_ABS/03-origin.git" 03-remotes-alice
git -c core.autocrlf=false clone -q "$ROOT_ABS/03-origin.git" 03-remotes-bob
(
    cd 03-remotes-alice
    configure_repo
    git config user.name "Alice Example"
    git config user.email "alice@example.com"
    git checkout -q main
    git remote set-head origin -d >/dev/null 2>&1 || true
)
(
    cd 03-remotes-bob
    configure_repo
    git config user.name "Bob Example"
    git config user.email "bob@example.com"
    git checkout -q main
    git remote set-head origin -d >/dev/null 2>&1 || true
)

# -----------------------------------------------------------------------------
# Lecture 01C scenarios. These are cloned from the immutable seed so
# Lecture 01B's push/fetch demo cannot contaminate them.
# -----------------------------------------------------------------------------
say "Preparing 04-merge"
clone_from_seed 04-merge
(
    cd 04-merge
    git branch feature/validation origin/feature/validation
    git remote remove origin
    git checkout -q main
)

say "Preparing 05-rebase"
clone_from_seed 05-rebase
(
    cd 05-rebase
    git branch feature/validation origin/feature/validation
    git remote remove origin
    git checkout -q feature/validation
)

say "Preparing 06-interactive-rebase"
make_local_scenario 06-interactive-rebase
(
    cd 06-interactive-rebase
    strip_tags
    git checkout -q -b feature/parser
    mkdir -p tests

    cat > src/parser.sh <<'TXT'
#!/usr/bin/env bash

parse_port() {
    local value="$1"
    printf '%s\n' "$value"
}
TXT
    chmod +x src/parser.sh
    git add src/parser.sh
    git commit -q -m "Implement parser"

    cat >> src/parser.sh <<'TXT'

# temporary debugging helper
printf_debug() {
    printf 'DEBUG: %s\n' "$1"
}
TXT
    git add src/parser.sh
    git commit -q -m "oops add debug helper"

    cat > tests/test-parser.sh <<'TXT'
#!/usr/bin/env bash
set -euo pipefail

source src/parser.sh
[[ "$(parse_port 8080)" == "8080" ]]
echo "parser tests passed"
TXT
    chmod +x tests/test-parser.sh
    git add tests/test-parser.sh
    git commit -q -m "fix test"

    sed -i.bak '/# temporary debugging helper/,$d' src/parser.sh
    rm -f src/parser.sh.bak
    git add src/parser.sh
    git commit -q -m "remove debug output"
)

say "Preparing 07-conflict"
make_local_scenario 07-conflict
(
    cd 07-conflict
    strip_tags

    git checkout -q -b feature/conflict
    sed -i.bak 's/^timeout=30$/timeout=DEFAULT_TIMEOUT/' config.properties
    rm -f config.properties.bak
    git add config.properties
    git commit -q -m "Use named default timeout"

    git checkout -q main
    sed -i.bak 's/^timeout=30$/timeout=60/' config.properties
    rm -f config.properties.bak
    git add config.properties
    git commit -q -m "Increase default timeout"
)

say "Preparing 08-reset-reflog"
make_local_scenario 08-reset-reflog
(
    cd 08-reset-reflog
    for tag in A B C D E; do
        git tag -d "$tag" >/dev/null
    done

    printf '\nRecovery demo line 1\n' >> README.md
    git add README.md
    git commit -q -m "Add recovery demo note"

    printf 'demo.mode=true\n' >> config.properties
    git add config.properties
    git commit -q -m "Enable demo mode"

    cat > RECOVERY.txt <<'TXT'
This file exists so we can apparently lose it with reset --hard and recover it
using the reflog.
TXT
    git add RECOVERY.txt
    git commit -q -m "Add recovery marker"
)

say "Preparing 09-bisect"
make_local_scenario 09-bisect
(
    cd 09-bisect
    strip_tags
    git checkout -q -b demo/bisect
    mkdir -p tests

    cat > src/compute.sh <<'TXT'
#!/usr/bin/env bash

normalize_timeout() {
    local value="$1"
    printf '%s\n' "$value"
}
TXT
    chmod +x src/compute.sh

    cat > tests/test-compute.sh <<'TXT'
#!/usr/bin/env bash
set -euo pipefail

source src/compute.sh
[[ "$(normalize_timeout 30)" == "30" ]]
TXT
    chmod +x tests/test-compute.sh

    git add src/compute.sh tests/test-compute.sh
    git commit -q -m "Add timeout normalization"
    git tag bisect-good

    for n in 1 2 3 4; do
        printf 'pre-bug note %s\n' "$n" >> BISECT-NOTES.txt
        git add BISECT-NOTES.txt
        git commit -q -m "Document pre-bug change $n"
    done

    cat > src/compute.sh <<'TXT'
#!/usr/bin/env bash

normalize_timeout() {
    local value="$1"
    printf '%s\n' "$((value + 1))"
}
TXT
    chmod +x src/compute.sh
    git add src/compute.sh
    git commit -q -m "Refactor timeout normalization"

    for n in 1 2 3 4 5; do
        printf 'post-bug note %s\n' "$n" >> BISECT-NOTES.txt
        git add BISECT-NOTES.txt
        git commit -q -m "Document post-bug change $n"
    done

    git tag bisect-bad
)

# The canonical history and immutable seed are construction-only material.
rm -rf -- base seed.git

cat > README.md <<'EOF2'
# IA 01 Git Lab

This directory was generated by the supplied `build-git-lab.sh` script.

Each numbered directory is an independent scenario used by IA 01. Work only in the scenario named by the assignment part.

- `01-objects/`
- `02-staging/`
- `03-remotes-alice/` and `03-remotes-bob/`
- `04-merge/`
- `05-rebase/`
- `06-interactive-rebase/`
- `07-conflict/`
- `08-reset-reflog/`
- `09-bisect/`

`03-origin.git/` is the isolated remote used by the Alice/Bob scenario.

Do not store unrelated work in this generated directory. The reset script
destroys and recreates the entire lab. Capture any evidence you need before
resetting.
EOF2

say "Done"
printf '\nCreated: %s\n' "$ROOT_ABS"
printf 'Next, run: bash ./check-git-lab.sh %s\n' "$ROOT_ABS"
printf 'Started from: %s\n' "$START_DIR"
