# Directory Encryption Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `md-age git dir-clean`, `dir-smudge`, and `add-dir` subcommands for transparent directory encryption via git clean/smudge filters.

**Design:** See `docs/plans/2026-02-11-directory-encryption-design.md`

**Architecture:** Extend `bin/md-age` with new git subcommands. New helper functions for `.age-recipients` walk-up resolution. Reuse existing caching, identity, and encryption infrastructure.

**Tech Stack:** Bash, age CLI, git config, SHA256 (via shasum)

---

### Task 1: .age-recipients walk-up resolution

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing tests**

```bash
test_find_age_recipients_in_dir() {
    # .age-recipients in the same directory as the file
    local dir="$TMPDIR/find-recip"
    mkdir -p "$dir/secrets"
    git init -q "$dir"
    echo "$RECIPIENT" > "$dir/secrets/.age-recipients"

    local result
    result=$(cd "$dir" && source "$MD_AGE" --source-helpers && find_age_recipients "secrets/file.txt")
    [[ "$result" == *"secrets/.age-recipients"* ]]
}

test_find_age_recipients_walks_up() {
    # .age-recipients at repo root, file in subdirectory
    local dir="$TMPDIR/find-recip-up"
    mkdir -p "$dir/secrets/nested"
    git init -q "$dir"
    echo "$RECIPIENT" > "$dir/.age-recipients"

    local result
    result=$(cd "$dir" && source "$MD_AGE" --source-helpers && find_age_recipients "secrets/nested/file.txt")
    [[ "$result" == *".age-recipients"* ]]
}

test_find_age_recipients_nearest_wins() {
    # Override: .age-recipients in subdir takes precedence over root
    local dir="$TMPDIR/find-recip-nearest"
    mkdir -p "$dir/secrets"
    git init -q "$dir"
    echo "root-recipient" > "$dir/.age-recipients"
    echo "dir-recipient" > "$dir/secrets/.age-recipients"

    local result
    result=$(cd "$dir" && source "$MD_AGE" --source-helpers && find_age_recipients "secrets/file.txt")
    grep -q "dir-recipient" "$result"
}

test_find_age_recipients_stops_at_git_root() {
    # .age-recipients above git root should not be found
    local dir="$TMPDIR/find-recip-root"
    mkdir -p "$dir/repo/secrets"
    echo "$RECIPIENT" > "$dir/.age-recipients"
    git init -q "$dir/repo"

    local result
    if result=$(cd "$dir/repo" && source "$MD_AGE" --source-helpers && find_age_recipients "secrets/file.txt" 2>/dev/null); then
        return 1  # Should have failed (no .age-recipients within repo)
    fi
    return 0
}

test_read_age_recipients_parses() {
    # Strips comments, blank lines, whitespace
    cat > "$TMPDIR/test-recipients" << EOF
# This is a comment
age1abc123

  ssh-ed25519 AAAAC3...
# Another comment

git:keys/editors
EOF

    local result
    result=$(source "$MD_AGE" --source-helpers && read_age_recipients "$TMPDIR/test-recipients")
    local count
    count=$(echo "$result" | wc -l | tr -d ' ')
    [[ "$count" -eq 3 ]] || return 1
    echo "$result" | grep -q "age1abc123" || return 1
    echo "$result" | grep -q "ssh-ed25519 AAAAC3..." || return 1
    echo "$result" | grep -q "git:keys/editors" || return 1
}
```

Note: These helpers are tested indirectly through `dir-clean` in Task 2, not in isolation. The walk-up logic, comment stripping, and error cases are all exercised through the dir-clean tests. No test-helper subcommand needed.

**Step 2: Implement helper functions**

Add to `bin/md-age`, after `build_recipient_args()`:

`find_age_recipients(filename)`:
1. Get the git repo root via `git rev-parse --show-toplevel`
2. Start from `dirname(filename)` (the `%f` path passed by git, relative to repo root)
3. Walk up: check for `.age-recipients` in current dir, then parent, stopping at repo root
4. If found, print the path and return 0
5. If not found, return 1

`read_age_recipients(filepath)`:
1. Read the file
2. Strip lines starting with `#` (comments)
3. Strip blank lines
4. Trim leading/trailing whitespace from each line
5. Output one recipient per line

**Step 3: Run tests, verify pass**

**Step 4: Commit**

```
feat(git): add .age-recipients walk-up resolution helpers
```

---

### Task 2: dir-clean filter

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing tests**

```bash
test_git_dir_clean_encrypts() {
    local repo="$TMPDIR/dir-clean-repo"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"

    local output
    output=$(cd "$repo" && echo '{"key": "value"}' | "$MD_AGE" git dir-clean secrets/config.json)

    # Should have frontmatter envelope
    echo "$output" | grep -q "^---$" || return 1
    echo "$output" | grep -q "^age-encrypt: yes$" || return 1
    echo "$output" | grep -q "$RECIPIENT" || return 1
    # Should have encrypted body
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1
    # Should NOT have plaintext
    ! echo "$output" | grep -q '"key"' || return 1
}

test_git_dir_clean_uses_nearest_recipients() {
    local repo="$TMPDIR/dir-clean-nearest"
    mkdir -p "$repo/secrets"
    git init -q "$repo"

    # Create second key for override
    local key2="$TMPDIR/dir-clean-key2.txt"
    age-keygen -o "$key2" 2>&1 | grep 'Public key:' | sed 's/Public key: //' > "$TMPDIR/dir-clean-recip2.txt"
    local recipient2
    recipient2=$(cat "$TMPDIR/dir-clean-recip2.txt")

    echo "$RECIPIENT" > "$repo/.age-recipients"
    echo "$recipient2" > "$repo/secrets/.age-recipients"

    local output
    output=$(cd "$repo" && echo "secret data" | "$MD_AGE" git dir-clean secrets/file.txt)

    # Envelope should have the override recipient, not root
    echo "$output" | grep -q "$recipient2" || return 1
    ! echo "$output" | grep -q "$RECIPIENT" || return 1
}

test_git_dir_clean_fails_no_recipients_file() {
    local repo="$TMPDIR/dir-clean-no-recip"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    # No .age-recipients anywhere

    if echo "data" | (cd "$repo" && "$MD_AGE" git dir-clean secrets/file.txt) 2>/dev/null; then
        return 1  # Should have failed
    fi
    return 0
}

test_git_dir_clean_deterministic() {
    local repo="$TMPDIR/dir-clean-cache"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"

    local input="some file content"
    local output1 output2
    output1=$(cd "$repo" && echo "$input" | "$MD_AGE" git dir-clean secrets/file.txt)
    output2=$(cd "$repo" && echo "$input" | "$MD_AGE" git dir-clean secrets/file.txt)

    [[ "$output1" == "$output2" ]] || return 1
}

test_git_dir_clean_envelope_is_valid_mdage() {
    # Envelope should be decryptable by md-age -d
    local repo="$TMPDIR/dir-clean-compat"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"

    local encrypted
    encrypted=$(cd "$repo" && echo "compatibility test" | "$MD_AGE" git dir-clean secrets/file.txt)

    local decrypted
    decrypted=$(echo "$encrypted" | "$MD_AGE" -d -i "$TESTKEY")
    echo "$decrypted" | grep -q "compatibility test"
}
```

**Step 2: Implement git_dir_clean()**

Add `git_dir_clean()` function and wire into subcommand routing (`dir-clean) shift; git_dir_clean "$@"`):

1. Read stdin (preserving trailing newlines, same pattern as `git_clean`)
2. Call `find_age_recipients "$filename"` — error if not found
3. Call `read_age_recipients` on the result
4. Call `build_recipient_args` to get age CLI args
5. Compute cache key: `compute_cache_key "$age_args" "$content"`
6. Check/populate cache (reuse `get_cached`/`set_cached`)
7. Encrypt with `age -e -a`
8. Build envelope: generate frontmatter with `age-encrypt: yes` and recipient list, then append ciphertext
9. Output envelope

**Step 3: Run tests, verify pass**

**Step 4: Commit**

```
feat(git): implement dir-clean filter for directory encryption
```

---

### Task 3: dir-smudge filter

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing tests**

```bash
test_git_dir_smudge_decrypts() {
    local repo="$TMPDIR/dir-smudge-repo"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"
    (cd "$repo" && "$MD_AGE" git config add -i "$TESTKEY") >/dev/null

    # Encrypt via dir-clean first
    local encrypted
    encrypted=$(cd "$repo" && echo "secret payload" | "$MD_AGE" git dir-clean secrets/data.bin)

    # Decrypt via dir-smudge
    local decrypted
    decrypted=$(cd "$repo" && echo "$encrypted" | "$MD_AGE" git dir-smudge secrets/data.bin)

    # Should get raw content back (no frontmatter)
    [[ "$decrypted" == "secret payload" ]]
}

test_git_dir_smudge_strips_envelope() {
    local repo="$TMPDIR/dir-smudge-strip"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"
    (cd "$repo" && "$MD_AGE" git config add -i "$TESTKEY") >/dev/null

    local encrypted
    encrypted=$(cd "$repo" && echo "raw data" | "$MD_AGE" git dir-clean secrets/file.txt)

    local decrypted
    decrypted=$(cd "$repo" && echo "$encrypted" | "$MD_AGE" git dir-smudge secrets/file.txt)

    # Must NOT contain frontmatter markers
    ! echo "$decrypted" | grep -q "^---$" || return 1
    ! echo "$decrypted" | grep -q "age-encrypt" || return 1
    echo "$decrypted" | grep -q "raw data"
}

test_git_dir_smudge_passthrough_no_identity() {
    local repo="$TMPDIR/dir-smudge-noid"
    mkdir -p "$repo/secrets"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"
    # No identity configured

    local encrypted
    encrypted=$(cd "$repo" && echo "data" | "$MD_AGE" git dir-clean secrets/file.txt)

    # Should pass through unchanged (no identity to decrypt)
    local output
    output=$(cd "$repo" && echo "$encrypted" | "$MD_AGE" git dir-smudge secrets/file.txt)
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_git_dir_smudge_passthrough_no_envelope() {
    local repo="$TMPDIR/dir-smudge-plain"
    git init -q "$repo"

    # Raw content without envelope should pass through
    local output
    output=$(cd "$repo" && echo "just plain text" | "$MD_AGE" git dir-smudge somefile.txt)
    [[ "$output" == "just plain text" ]]
}
```

**Step 2: Implement git_dir_smudge()**

Add `git_dir_smudge()` function and wire into subcommand routing:

1. Read stdin (preserving trailing newlines)
2. Parse frontmatter — if no frontmatter, pass through unchanged
3. Check for `age-encrypt: yes` — if absent, pass through unchanged
4. Check if body starts with AGE armor — if not, pass through
5. Get identities from git config — if none, pass through unchanged
6. Build identity args (same as existing `git_smudge`)
7. Decrypt the body
8. Output **only the decrypted content** — strip the entire envelope (this is the key difference from `git_smudge`, which preserves frontmatter)

**Step 3: Run tests, verify pass**

**Step 4: Commit**

```
feat(git): implement dir-smudge filter for directory decryption
```

---

### Task 4: add-dir helper command

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing tests**

```bash
test_git_add_dir_creates_marker() {
    local repo="$TMPDIR/add-dir-repo"
    git init -q "$repo"
    mkdir -p "$repo/secrets"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) || return 1

    [[ -f "$repo/secrets/.age-encrypt" ]]
}

test_git_add_dir_updates_gitattributes() {
    local repo="$TMPDIR/add-dir-attr"
    git init -q "$repo"
    mkdir -p "$repo/secrets"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) || return 1

    grep -q 'secrets/\*\* filter=md-age-dir diff=md-age-dir' "$repo/.gitattributes" || return 1
    grep -q 'secrets/.age-encrypt !filter !diff' "$repo/.gitattributes" || return 1
}

test_git_add_dir_idempotent() {
    local repo="$TMPDIR/add-dir-idem"
    git init -q "$repo"
    mkdir -p "$repo/secrets"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) || return 1
    (cd "$repo" && "$MD_AGE" git add-dir secrets) || return 1

    # Should only have one entry, not duplicates
    local count
    count=$(grep -c 'secrets/\*\* filter=md-age-dir' "$repo/.gitattributes")
    [[ "$count" -eq 1 ]]
}

test_git_add_dir_multiple_dirs() {
    local repo="$TMPDIR/add-dir-multi"
    git init -q "$repo"
    mkdir -p "$repo/secrets" "$repo/credentials"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) || return 1
    (cd "$repo" && "$MD_AGE" git add-dir credentials) || return 1

    grep -q 'secrets/\*\* filter=md-age-dir' "$repo/.gitattributes" || return 1
    grep -q 'credentials/\*\* filter=md-age-dir' "$repo/.gitattributes" || return 1
    [[ -f "$repo/secrets/.age-encrypt" ]] || return 1
    [[ -f "$repo/credentials/.age-encrypt" ]] || return 1
}

test_git_add_dir_creates_dir_if_missing() {
    local repo="$TMPDIR/add-dir-mkdir"
    git init -q "$repo"

    (cd "$repo" && "$MD_AGE" git add-dir newdir) || return 1

    [[ -d "$repo/newdir" ]] || return 1
    [[ -f "$repo/newdir/.age-encrypt" ]]
}

test_git_add_dir_excludes_local_recipients() {
    # If the dir has its own .age-recipients, exclude it from filter too
    local repo="$TMPDIR/add-dir-local-recip"
    git init -q "$repo"
    mkdir -p "$repo/secrets"
    echo "$RECIPIENT" > "$repo/secrets/.age-recipients"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) || return 1

    grep -q 'secrets/.age-recipients !filter !diff' "$repo/.gitattributes"
}
```

**Step 2: Implement git_add_dir()**

Add `git_add_dir()` function and wire into subcommand routing:

1. Accept directory path argument (strip trailing slash)
2. Check we're in a git repo
3. Create the directory if it doesn't exist (`mkdir -p`)
4. Create `.age-encrypt` marker (`touch "$dir/.age-encrypt"`)
5. Find repo root for `.gitattributes` location
6. Build `.gitattributes` lines:
   - `$dir/** filter=md-age-dir diff=md-age-dir`
   - `$dir/.age-encrypt !filter !diff`
   - If `$dir/.age-recipients` exists: `$dir/.age-recipients !filter !diff`
7. Check `.gitattributes` for existing entries (idempotent)
8. Append new lines if not already present
9. Print what was done

**Step 3: Run tests, verify pass**

**Step 4: Commit**

```
feat(git): implement add-dir helper command
```

---

### Task 5: Update git init to register md-age-dir filter

**Files:**
- Modify: `bin/md-age`
- Test: `t/md-age-test.sh`

**Step 1: Write failing test**

```bash
test_git_init_registers_dir_filter() {
    local repo="$TMPDIR/init-dir-filter"
    git init -q "$repo"

    (cd "$repo" && "$MD_AGE" git init) || return 1

    (cd "$repo" && git config --get filter.md-age-dir.clean) | grep -q "dir-clean" || return 1
    (cd "$repo" && git config --get filter.md-age-dir.smudge) | grep -q "dir-smudge" || return 1
    (cd "$repo" && git config --get filter.md-age-dir.required) | grep -q "true" || return 1
    (cd "$repo" && git config --get diff.md-age-dir.textconv) | grep -q "dir-smudge" || return 1
}
```

**Step 2: Update git_init()**

Add to the existing `git_init()` function, after the existing `md-age` filter setup:

```bash
# Set up directory encryption filter
git config filter.md-age-dir.clean "$cmd_prefix git dir-clean %f"
git config filter.md-age-dir.smudge "$cmd_prefix git dir-smudge %f"
git config filter.md-age-dir.required true

# Set up diff for directory encryption
git config diff.md-age-dir.textconv "sh -c 'cat \"\$1\" | $cmd_prefix git dir-smudge \"\$1\"' --"
```

**Step 3: Update existing test**

The existing `test_git_init` test should still pass (it only checks for `md-age` filter, not `md-age-dir`). No changes needed to existing tests.

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```
feat(git): register md-age-dir filter in git init
```

---

### Task 6: End-to-end integration test

**Files:**
- Test: `t/md-age-test.sh`

**Step 1: Write integration test**

```bash
test_git_dir_integration_workflow() {
    local repo="$TMPDIR/dir-integration-repo"
    git init -q "$repo"
    cd "$repo"

    export PATH="$PROJECT_DIR/bin:$PATH"

    # Setup
    "$MD_AGE" git init >/dev/null
    "$MD_AGE" git config add -i "$TESTKEY" >/dev/null
    echo "$RECIPIENT" > .age-recipients
    "$MD_AGE" git add-dir secrets >/dev/null

    git add .age-recipients .gitattributes secrets/.age-encrypt
    git commit -q -m "Initial setup"

    # Create files in encrypted directory
    echo '{"api_key": "abc123"}' > secrets/config.json
    echo "password=hunter2" > secrets/creds.txt

    git add secrets/
    git commit -q -m "Add secrets"

    # Verify committed content is encrypted
    local stored
    stored=$(git show HEAD:secrets/config.json)
    if echo "$stored" | grep -q "abc123"; then
        echo "FAIL: plaintext found in git (config.json)" >&2
        return 1
    fi
    if ! echo "$stored" | grep -q "BEGIN AGE ENCRYPTED FILE"; then
        echo "FAIL: no encrypted content in git (config.json)" >&2
        return 1
    fi

    stored=$(git show HEAD:secrets/creds.txt)
    if echo "$stored" | grep -q "hunter2"; then
        echo "FAIL: plaintext found in git (creds.txt)" >&2
        return 1
    fi

    # Verify working copy is decrypted
    grep -q "abc123" secrets/config.json || {
        echo "FAIL: working copy not decrypted (config.json)" >&2
        return 1
    }
    grep -q "hunter2" secrets/creds.txt || {
        echo "FAIL: working copy not decrypted (creds.txt)" >&2
        return 1
    }

    # Verify checkout re-decrypts
    git checkout -- secrets/
    grep -q "abc123" secrets/config.json || {
        echo "FAIL: checkout did not decrypt (config.json)" >&2
        return 1
    }

    # Verify .age-encrypt is not encrypted
    stored=$(git show HEAD:secrets/.age-encrypt)
    ! echo "$stored" | grep -q "BEGIN AGE ENCRYPTED FILE" || {
        echo "FAIL: .age-encrypt was encrypted" >&2
        return 1
    }

    return 0
}

test_git_dir_binary_roundtrip() {
    local repo="$TMPDIR/dir-binary-repo"
    git init -q "$repo"
    cd "$repo"

    export PATH="$PROJECT_DIR/bin:$PATH"

    "$MD_AGE" git init >/dev/null
    "$MD_AGE" git config add -i "$TESTKEY" >/dev/null
    echo "$RECIPIENT" > .age-recipients
    "$MD_AGE" git add-dir assets >/dev/null
    git add .age-recipients .gitattributes assets/.age-encrypt
    git commit -q -m "Setup"

    # Create a binary file (random bytes)
    dd if=/dev/urandom of=assets/random.bin bs=256 count=1 2>/dev/null
    local orig_hash
    orig_hash=$(shasum -a 256 < assets/random.bin | cut -d' ' -f1)

    git add assets/random.bin
    git commit -q -m "Add binary"

    # Verify git stores encrypted
    local stored
    stored=$(git show HEAD:assets/random.bin)
    echo "$stored" | grep -q "BEGIN AGE ENCRYPTED FILE" || {
        echo "FAIL: binary not encrypted in git" >&2
        return 1
    }

    # Verify checkout restores exact bytes
    git checkout -- assets/random.bin
    local restored_hash
    restored_hash=$(shasum -a 256 < assets/random.bin | cut -d' ' -f1)

    [[ "$orig_hash" == "$restored_hash" ]] || {
        echo "FAIL: binary roundtrip mismatch" >&2
        return 1
    }
}

test_git_dir_rekey() {
    local repo="$TMPDIR/dir-rekey-repo"
    git init -q "$repo"
    cd "$repo"

    export PATH="$PROJECT_DIR/bin:$PATH"

    # Setup with first recipient
    "$MD_AGE" git init >/dev/null
    "$MD_AGE" git config add -i "$TESTKEY" >/dev/null
    echo "$RECIPIENT" > .age-recipients
    "$MD_AGE" git add-dir secrets >/dev/null
    echo "secret data" > secrets/file.txt
    git add .age-recipients .gitattributes secrets/
    git commit -q -m "Initial"

    # Add second recipient
    local key2="$TMPDIR/rekey-key2.txt"
    age-keygen -o "$key2" 2>&1 | grep 'Public key:' | sed 's/Public key: //' > "$TMPDIR/rekey-recip2.txt"
    local recipient2
    recipient2=$(cat "$TMPDIR/rekey-recip2.txt")

    printf '%s\n%s\n' "$RECIPIENT" "$recipient2" > .age-recipients

    # Rekey
    "$MD_AGE" git rekey secrets/ || return 1

    # Verify new recipient can decrypt
    local stored
    stored=$(git show :secrets/file.txt)
    local decrypted
    decrypted=$(echo "$stored" | "$MD_AGE" -d -i "$key2")
    echo "$decrypted" | grep -q "secret data" || {
        echo "FAIL: new recipient cannot decrypt after rekey" >&2
        return 1
    }
}
```

**Step 2: Run tests, verify pass**

All tests should pass using the implementations from Tasks 1-5.

**Step 3: Commit**

```
test(git): add integration tests for directory encryption
```

---

### Task 7: Update git help and usage text

**Files:**
- Modify: `bin/md-age`

**Step 1: Update usage strings**

Update `usage()` to mention directory encryption in the git integration section.

Update `git_usage()` to list the new subcommands:

```
git subcommands for transparent encryption:
  init              Set up filters in current repo
  config            Manage identity configuration
  add-dir <path>    Set up a directory for encryption
  clean             Encrypt filter for md-age markdown (for git)
  smudge            Decrypt filter for md-age markdown (for git)
  dir-clean         Encrypt filter for directory mode (for git)
  dir-smudge        Decrypt filter for directory mode (for git)
  rekey [files...]  Re-encrypt files (use after adding recipients)
```

**Step 2: Verify existing help test still passes**

```bash
run_test "git subcommand shows help" test_git_help
```

**Step 3: Commit**

```
docs: update help text for directory encryption commands
```

---

## Summary

After completing all tasks:

1. `find_age_recipients()` / `read_age_recipients()` — walk-up resolution for `.age-recipients`
2. `md-age git dir-clean` — encrypts arbitrary files into frontmatter envelope
3. `md-age git dir-smudge` — decrypts envelope back to raw file content
4. `md-age git add-dir` — sets up a directory for encryption (`.age-encrypt` + `.gitattributes`)
5. `md-age git init` — registers both `md-age` and `md-age-dir` filters
6. Integration tests cover: text files, binary files, rekey, multi-directory setup

The existing `md-age` filter for markdown files is unchanged. Both filters share the same identity configuration (`md-age.config.identity`) and hash cache (`.git/md-age/hashes/`).
