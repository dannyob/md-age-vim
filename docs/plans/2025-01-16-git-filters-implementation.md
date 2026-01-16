# Git Filters Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `md-age git` subcommands for transparent encryption via smudge/clean filters.

**Architecture:** Extend existing `bin/md-age` bash script with a `git` subcommand that routes to `init`, `config`, `clean`, and `smudge` sub-subcommands. Hash caching in `.git/md-age/hashes/` prevents spurious modifications.

**Tech Stack:** Bash, age CLI, git config, SHA256 (via shasum)

---

### Task 1: Add git subcommand routing

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing test for git subcommand**

Add to `t/md-age-test.sh` before the `main()` function:

```bash
test_git_help() {
    "$MD_AGE" git --help 2>&1 | grep -q "git subcommands"
}
```

And add to the test runner in `main()`:

```bash
run_test "git subcommand shows help" test_git_help
```

**Step 2: Run test to verify it fails**

Run: `./t/md-age-test.sh`
Expected: FAIL - "git subcommands" not found

**Step 3: Implement git subcommand routing**

In `bin/md-age`, add git_usage() function after the existing usage() function:

```bash
git_usage() {
    cat <<'EOF'
Usage: md-age git <command> [options]

git subcommands for transparent encryption:
  init              Set up filters in current repo
  config            Manage identity configuration
  clean             Encrypt filter (for git)
  smudge            Decrypt filter (for git)

Run 'md-age git <command> --help' for command-specific help.
EOF
    exit "${1:-0}"
}
```

Then add routing before the getopts loop (around line 117):

```bash
# Route to git subcommand if first arg is "git"
if [[ "${1:-}" == "git" ]]; then
    shift
    case "${1:-}" in
        init)   shift; git_init "$@" ;;
        config) shift; git_config "$@" ;;
        clean)  shift; git_clean "$@" ;;
        smudge) shift; git_smudge "$@" ;;
        -h|--help|"") git_usage 0 ;;
        *) die "unknown git command: $1" ;;
    esac
    exit 0
fi
```

Add stub functions after git_usage():

```bash
git_init() { die "git init not yet implemented"; }
git_config() { die "git config not yet implemented"; }
git_clean() { die "git clean not yet implemented"; }
git_smudge() { die "git smudge not yet implemented"; }
```

**Step 4: Run test to verify it passes**

Run: `./t/md-age-test.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/md-age t/md-age-test.sh
git commit -m "feat(git): add git subcommand routing"
```

---

### Task 2: Implement git init

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing test for git init**

Add test function:

```bash
test_git_init() {
    # Create temp git repo
    local repo="$TMPDIR/test-repo"
    git init -q "$repo"

    # Run init
    (cd "$repo" && "$MD_AGE" git init) || return 1

    # Check filter config was added
    (cd "$repo" && git config --get filter.md-age.clean) | grep -q "md-age git clean" || return 1
    (cd "$repo" && git config --get filter.md-age.smudge) | grep -q "md-age git smudge" || return 1
    (cd "$repo" && git config --get filter.md-age.required) | grep -q "true" || return 1
    (cd "$repo" && git config --get diff.md-age.textconv) | grep -q "md-age git smudge" || return 1
}
```

Add to runner:

```bash
run_test "git init sets up filters" test_git_init
```

**Step 2: Run test to verify it fails**

Run: `./t/md-age-test.sh`
Expected: FAIL - "git init not yet implemented"

**Step 3: Implement git_init**

Replace the stub:

```bash
git_init() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: md-age git init

Set up md-age filter configuration in the current git repository.
Adds filter and diff settings to .git/config.

After running this, add to your .gitattributes:
  *.md filter=md-age diff=md-age
EOF
        exit 0
    fi

    # Check we're in a git repo
    git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"

    # Set up filter
    git config filter.md-age.clean "md-age git clean %f"
    git config filter.md-age.smudge "md-age git smudge %f"
    git config filter.md-age.required true

    # Set up diff
    git config diff.md-age.textconv "md-age git smudge"

    echo "md-age: filter configured in .git/config"
    echo "md-age: add '*.md filter=md-age diff=md-age' to .gitattributes"
}
```

**Step 4: Run test to verify it passes**

Run: `./t/md-age-test.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/md-age t/md-age-test.sh
git commit -m "feat(git): implement git init command"
```

---

### Task 3: Implement git config add/list

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing tests for git config**

```bash
test_git_config_add() {
    local repo="$TMPDIR/config-repo"
    git init -q "$repo"

    (cd "$repo" && "$MD_AGE" git config add -i "$TESTKEY") || return 1

    # Check identity was added
    (cd "$repo" && git config --get-all md-age.config.identity) | grep -q "$TESTKEY" || return 1
}

test_git_config_list() {
    local repo="$TMPDIR/list-repo"
    git init -q "$repo"

    (cd "$repo" && "$MD_AGE" git config add -i "$TESTKEY") || return 1

    local output
    output=$(cd "$repo" && "$MD_AGE" git config list)
    echo "$output" | grep -q "$TESTKEY" || return 1
}

test_git_config_multiple_identities() {
    local repo="$TMPDIR/multi-repo"
    git init -q "$repo"
    local key2="$TMPDIR/key2-config.txt"
    age-keygen -o "$key2" 2>/dev/null

    (cd "$repo" && "$MD_AGE" git config add -i "$TESTKEY") || return 1
    (cd "$repo" && "$MD_AGE" git config add -i "$key2") || return 1

    local count
    count=$(cd "$repo" && git config --get-all md-age.config.identity | wc -l)
    [[ "$count" -eq 2 ]] || return 1
}
```

Add to runner:

```bash
run_test "git config add adds identity" test_git_config_add
run_test "git config list shows identities" test_git_config_list
run_test "git config supports multiple identities" test_git_config_multiple_identities
```

**Step 2: Run tests to verify they fail**

Run: `./t/md-age-test.sh`
Expected: FAIL

**Step 3: Implement git_config**

Replace the stub:

```bash
git_config() {
    local cmd="${1:-}"

    case "$cmd" in
        -h|--help|"")
            cat <<'EOF'
Usage: md-age git config <command>

Commands:
  add -i <path>     Add an identity file
  list              List configured identities
  remove -i <path>  Remove an identity file

Identities are stored in .git/config (not version controlled).
EOF
            exit 0
            ;;
        add)
            shift
            git_config_add "$@"
            ;;
        list)
            git_config_list
            ;;
        remove)
            shift
            git_config_remove "$@"
            ;;
        *)
            die "unknown config command: $cmd"
            ;;
    esac
}

git_config_add() {
    local identity=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i) identity="$2"; shift 2 ;;
            *) die "unknown option: $1" ;;
        esac
    done

    [[ -n "$identity" ]] || die "no identity specified (-i)"
    git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"

    # Expand ~ but store the expanded path
    local expanded="${identity/#\~/$HOME}"

    # Check if already added
    if git config --get-all md-age.config.identity 2>/dev/null | grep -qF "$expanded"; then
        echo "md-age: identity already configured: $expanded"
        return 0
    fi

    git config --add md-age.config.identity "$expanded"
    echo "md-age: added identity: $expanded"
}

git_config_list() {
    git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"

    local identities
    identities=$(git config --get-all md-age.config.identity 2>/dev/null || true)

    if [[ -z "$identities" ]]; then
        echo "md-age: no identities configured"
        echo "md-age: use 'md-age git config add -i <path>' to add one"
        return 0
    fi

    echo "Identities:"
    while IFS= read -r id; do
        echo "  $id"
    done <<< "$identities"
}

git_config_remove() {
    local identity=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i) identity="$2"; shift 2 ;;
            *) die "unknown option: $1" ;;
        esac
    done

    [[ -n "$identity" ]] || die "no identity specified (-i)"
    git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"

    local expanded="${identity/#\~/$HOME}"

    if git config --unset md-age.config.identity "$expanded" 2>/dev/null; then
        echo "md-age: removed identity: $expanded"
    else
        die "identity not found: $expanded"
    fi
}
```

**Step 4: Run tests to verify they pass**

Run: `./t/md-age-test.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/md-age t/md-age-test.sh
git commit -m "feat(git): implement git config add/list/remove"
```

---

### Task 4: Implement git clean (encrypt filter) - basic

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing test for basic clean**

```bash
test_git_clean_passthrough() {
    # Non-md-age file should pass through unchanged
    local input="# Just a readme

Some content here."

    local output
    output=$(echo "$input" | "$MD_AGE" git clean test.md)

    [[ "$output" == "$input" ]] || return 1
}

test_git_clean_encrypts() {
    local repo="$TMPDIR/clean-repo"
    git init -q "$repo"
    (cd "$repo" && "$MD_AGE" git init) >/dev/null

    local input="---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Secret content"

    local output
    output=$(cd "$repo" && echo "$input" | "$MD_AGE" git clean test.md)

    # Should have frontmatter
    echo "$output" | grep -q "^---$" || return 1
    echo "$output" | grep -q "^age-encrypt: yes$" || return 1
    # Should have encrypted body
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1
    # Should NOT have plaintext
    echo "$output" | grep -qv "Secret content" || return 1
}

test_git_clean_fails_no_recipients() {
    local input="---
age-encrypt: yes
---
Secret content"

    if echo "$input" | "$MD_AGE" git clean test.md 2>/dev/null; then
        return 1  # Should have failed
    fi
    return 0
}
```

Add to runner:

```bash
run_test "git clean passes through non-md-age files" test_git_clean_passthrough
run_test "git clean encrypts md-age files" test_git_clean_encrypts
run_test "git clean fails without recipients" test_git_clean_fails_no_recipients
```

**Step 2: Run tests to verify they fail**

Run: `./t/md-age-test.sh`
Expected: FAIL

**Step 3: Implement basic git_clean**

Replace the stub:

```bash
git_clean() {
    local filename="${1:-}"

    if [[ "$filename" == "-h" ]] || [[ "$filename" == "--help" ]]; then
        cat <<'EOF'
Usage: md-age git clean <filename>

Git clean filter - encrypts md-age files on stage.
Reads from stdin, writes to stdout.
Non-md-age files pass through unchanged.
EOF
        exit 0
    fi

    # Read all stdin
    local content
    content=$(cat)

    # Parse frontmatter
    if ! parse_frontmatter "$content"; then
        # No frontmatter - pass through
        printf '%s\n' "$content"
        return 0
    fi

    local frontmatter="$FRONTMATTER"
    local body="$BODY"
    body="${body%$'\n'}"  # Remove trailing newline

    # Check if this is an md-age file
    if ! echo "$frontmatter" | grep -q '^age-encrypt: yes'; then
        # Not an md-age file - pass through
        printf '%s\n' "$content"
        return 0
    fi

    # Extract recipients
    local recipients
    recipients=$(echo "$frontmatter" | extract_recipients)

    if [[ -z "$recipients" ]]; then
        echo "md-age: clean: no recipients in frontmatter for $filename" >&2
        exit 1
    fi

    # Build recipient args and encrypt
    local age_args
    age_args=$(build_recipient_args "$recipients")

    local encrypted
    encrypted=$(echo "$body" | $age_cmd -e -a $age_args) || {
        echo "md-age: clean: encryption failed for $filename" >&2
        exit 1
    }

    # Output frontmatter + encrypted body
    printf '%s' "$frontmatter"
    printf '%s\n' "$encrypted"
}
```

**Step 4: Run tests to verify they pass**

Run: `./t/md-age-test.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/md-age t/md-age-test.sh
git commit -m "feat(git): implement basic git clean filter"
```

---

### Task 5: Implement git smudge (decrypt filter)

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing tests for smudge**

```bash
test_git_smudge_passthrough_plain() {
    # Non-md-age file passes through
    local input="# Just a readme"
    local output
    output=$(echo "$input" | "$MD_AGE" git smudge test.md)
    [[ "$output" == "$input" ]]
}

test_git_smudge_passthrough_no_identity() {
    local repo="$TMPDIR/smudge-noid-repo"
    git init -q "$repo"

    # Encrypted content but no identity configured
    local input="---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
-----BEGIN AGE ENCRYPTED FILE-----
YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBIckxLbXdTYU0rWVk4UmVu
-----END AGE ENCRYPTED FILE-----"

    # Should pass through without error (no identity)
    local output
    output=$(cd "$repo" && echo "$input" | "$MD_AGE" git smudge test.md 2>&1) || return 1
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_git_smudge_decrypts() {
    local repo="$TMPDIR/smudge-repo"
    git init -q "$repo"
    (cd "$repo" && "$MD_AGE" git init && "$MD_AGE" git config add -i "$TESTKEY") >/dev/null

    # First encrypt something
    local plaintext="---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Secret smudge content"

    local encrypted
    encrypted=$(echo "$plaintext" | "$MD_AGE" git clean test.md)

    # Then decrypt via smudge
    local decrypted
    decrypted=$(cd "$repo" && echo "$encrypted" | "$MD_AGE" git smudge test.md)

    echo "$decrypted" | grep -q "Secret smudge content"
}
```

Add to runner:

```bash
run_test "git smudge passes through non-md-age files" test_git_smudge_passthrough_plain
run_test "git smudge passes through when no identity" test_git_smudge_passthrough_no_identity
run_test "git smudge decrypts with identity" test_git_smudge_decrypts
```

**Step 2: Run tests to verify they fail**

Run: `./t/md-age-test.sh`
Expected: FAIL

**Step 3: Implement git_smudge**

Replace the stub:

```bash
git_smudge() {
    local filename="${1:-}"

    if [[ "$filename" == "-h" ]] || [[ "$filename" == "--help" ]]; then
        cat <<'EOF'
Usage: md-age git smudge <filename>

Git smudge filter - decrypts md-age files on checkout.
Reads from stdin, writes to stdout.
Non-md-age files pass through unchanged.
If no identity configured, encrypted files pass through unchanged.
EOF
        exit 0
    fi

    # Read all stdin
    local content
    content=$(cat)

    # Parse frontmatter
    if ! parse_frontmatter "$content"; then
        # No frontmatter - pass through
        printf '%s\n' "$content"
        return 0
    fi

    local frontmatter="$FRONTMATTER"
    local body="$BODY"
    body="${body%$'\n'}"

    # Check if this is an md-age file
    if ! echo "$frontmatter" | grep -q '^age-encrypt: yes'; then
        printf '%s\n' "$content"
        return 0
    fi

    # Check if body is encrypted
    if [[ "$body" != *"-----BEGIN AGE ENCRYPTED FILE-----"* ]]; then
        # Not encrypted - pass through (new file perhaps)
        printf '%s\n' "$content"
        return 0
    fi

    # Get identities from git config
    local identities
    identities=$(git config --get-all md-age.config.identity 2>/dev/null || true)

    if [[ -z "$identities" ]]; then
        # No identity - pass through encrypted
        printf '%s\n' "$content"
        return 0
    fi

    # Build identity args
    local id_args=""
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        id_args="$id_args -i $id"
    done <<< "$identities"

    # Try to decrypt
    local decrypted
    if decrypted=$(echo "$body" | $age_cmd -d $id_args 2>/dev/null); then
        # Success - output frontmatter + decrypted
        printf '%s' "$frontmatter"
        printf '%s\n' "$decrypted"
    else
        # Decrypt failed - pass through encrypted
        printf '%s\n' "$content"
    fi
}
```

**Step 4: Run tests to verify they pass**

Run: `./t/md-age-test.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/md-age t/md-age-test.sh
git commit -m "feat(git): implement git smudge filter"
```

---

### Task 6: Implement hash caching for git clean

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing test for hash caching**

```bash
test_git_clean_deterministic() {
    local repo="$TMPDIR/cache-repo"
    git init -q "$repo"
    (cd "$repo" && "$MD_AGE" git init) >/dev/null

    local input="---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Deterministic test content"

    # Run clean twice - should get same output due to caching
    local output1 output2
    output1=$(cd "$repo" && echo "$input" | "$MD_AGE" git clean test.md)
    output2=$(cd "$repo" && echo "$input" | "$MD_AGE" git clean test.md)

    [[ "$output1" == "$output2" ]] || return 1
}

test_git_clean_cache_invalidates_on_change() {
    local repo="$TMPDIR/cache-change-repo"
    git init -q "$repo"
    (cd "$repo" && "$MD_AGE" git init) >/dev/null

    local input1="---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Content version 1"

    local input2="---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Content version 2"

    local output1 output2
    output1=$(cd "$repo" && echo "$input1" | "$MD_AGE" git clean test.md)
    output2=$(cd "$repo" && echo "$input2" | "$MD_AGE" git clean test.md)

    # Different content should produce different output
    [[ "$output1" != "$output2" ]] || return 1
}
```

Add to runner:

```bash
run_test "git clean is deterministic with caching" test_git_clean_deterministic
run_test "git clean cache invalidates on content change" test_git_clean_cache_invalidates_on_change
```

**Step 2: Run tests to verify they fail**

Run: `./t/md-age-test.sh`
Expected: First test FAIL (non-deterministic output), second may pass by luck

**Step 3: Add caching functions**

Add after the git_usage() function:

```bash
# Compute cache key for content
# Key = SHA256(sorted_recipients || NUL || body)
compute_cache_key() {
    local recipients="$1"
    local body="$2"

    # Sort recipients for consistency
    local sorted_recipients
    sorted_recipients=$(echo "$recipients" | sort)

    # Compute hash
    printf '%s\0%s' "$sorted_recipients" "$body" | shasum -a 256 | cut -d' ' -f1
}

# Get cache directory (creates if needed)
get_cache_dir() {
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    local cache_dir="$git_dir/md-age/hashes"
    mkdir -p "$cache_dir"
    echo "$cache_dir"
}

# Get cached ciphertext for key, returns 1 if not found
get_cached() {
    local key="$1"
    local cache_dir
    cache_dir=$(get_cache_dir) || return 1

    local prefix="${key:0:2}"
    local cache_file="$cache_dir/$prefix/$key"

    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi
    return 1
}

# Store ciphertext in cache
set_cached() {
    local key="$1"
    local ciphertext="$2"
    local cache_dir
    cache_dir=$(get_cache_dir) || return 1

    local prefix="${key:0:2}"
    mkdir -p "$cache_dir/$prefix"
    local cache_file="$cache_dir/$prefix/$key"

    printf '%s' "$ciphertext" > "$cache_file"
}
```

**Step 4: Update git_clean to use caching**

Replace the encryption section in git_clean (after extracting recipients):

```bash
    # Compute cache key
    local cache_key
    cache_key=$(compute_cache_key "$recipients" "$body")

    # Check cache
    local encrypted
    if encrypted=$(get_cached "$cache_key" 2>/dev/null); then
        # Cache hit - use cached ciphertext
        printf '%s' "$frontmatter"
        printf '%s\n' "$encrypted"
        return 0
    fi

    # Cache miss - encrypt
    local age_args
    age_args=$(build_recipient_args "$recipients")

    encrypted=$(echo "$body" | $age_cmd -e -a $age_args) || {
        echo "md-age: clean: encryption failed for $filename" >&2
        exit 1
    }

    # Store in cache
    set_cached "$cache_key" "$encrypted" 2>/dev/null || true

    # Output frontmatter + encrypted body
    printf '%s' "$frontmatter"
    printf '%s\n' "$encrypted"
```

**Step 5: Run tests to verify they pass**

Run: `./t/md-age-test.sh`
Expected: PASS

**Step 6: Commit**

```bash
git add bin/md-age t/md-age-test.sh
git commit -m "feat(git): add hash caching for deterministic clean output"
```

---

### Task 7: End-to-end integration test

**Files:**
- Test: `t/md-age-test.sh`

**Step 1: Write integration test**

```bash
test_git_integration_workflow() {
    local repo="$TMPDIR/integration-repo"
    git init -q "$repo"
    cd "$repo"

    # Setup
    "$MD_AGE" git init >/dev/null
    "$MD_AGE" git config add -i "$TESTKEY" >/dev/null
    echo '*.md filter=md-age diff=md-age' > .gitattributes
    git add .gitattributes
    git commit -q -m "Add gitattributes"

    # Create md-age file
    cat > secret.md << EOF
---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
This is secret content
EOF

    # Add and commit
    git add secret.md
    git commit -q -m "Add secret"

    # Verify committed content is encrypted
    local stored
    stored=$(git show HEAD:secret.md)
    if echo "$stored" | grep -q "This is secret content"; then
        echo "FAIL: plaintext found in git" >&2
        return 1
    fi
    if ! echo "$stored" | grep -q "BEGIN AGE ENCRYPTED FILE"; then
        echo "FAIL: no encrypted content in git" >&2
        return 1
    fi

    # Verify working copy is decrypted (via smudge)
    local working
    working=$(cat secret.md)
    if ! echo "$working" | grep -q "This is secret content"; then
        echo "FAIL: working copy not decrypted" >&2
        return 1
    fi

    # Verify checkout decrypts
    git checkout -- secret.md
    working=$(cat secret.md)
    if ! echo "$working" | grep -q "This is secret content"; then
        echo "FAIL: checkout did not decrypt" >&2
        return 1
    fi

    return 0
}
```

Add to runner:

```bash
run_test "git integration: add/commit/checkout workflow" test_git_integration_workflow
```

**Step 2: Run test**

Run: `./t/md-age-test.sh`
Expected: PASS (all previous work should make this pass)

**Step 3: Commit**

```bash
git add t/md-age-test.sh
git commit -m "test(git): add integration test for full workflow"
```

---

### Task 8: Update documentation

**Files:**
- Modify: `README.md` (if exists) or create minimal docs

**Step 1: Check for existing README**

Look for README.md in project root.

**Step 2: Add git filter documentation**

Add a section covering:
- `md-age git init`
- `md-age git config add -i <path>`
- Setting up `.gitattributes`
- How the workflow works

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add git filter usage documentation"
```

---

## Summary

After completing all tasks, the `md-age git` commands will be fully functional:

1. `md-age git init` - sets up filters
2. `md-age git config add/list/remove` - manages identities
3. `md-age git clean` - encrypts on stage (with caching)
4. `md-age git smudge` - decrypts on checkout

The hash caching ensures deterministic output for unchanged files, preventing spurious "modified" status in git.
