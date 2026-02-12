#!/usr/bin/env bash
#
# Tests for bin/md-age
#
# Run: ./t/md-age-test.sh
# Or:  make test-cli

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MD_AGE="$PROJECT_DIR/bin/md-age"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TMPDIR=""
TESTKEY=""
RECIPIENT=""

# Colors (if terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    NC=''
fi

setup() {
    TMPDIR=$(mktemp -d)
    TESTKEY="$TMPDIR/key.txt"
    age-keygen -o "$TESTKEY" 2>&1 | grep 'Public key:' | sed 's/Public key: //' > "$TMPDIR/recipient.txt"
    RECIPIENT=$(cat "$TMPDIR/recipient.txt")
}

teardown() {
    [[ -n "$TMPDIR" ]] && rm -rf "$TMPDIR"
}

pass() {
    ((TESTS_PASSED++)) || true
    if [[ -n "${TAP:-}" ]]; then
        echo "ok $TESTS_RUN - $1"
    else
        echo -e "${GREEN}✓${NC} $1"
    fi
}

fail() {
    ((TESTS_FAILED++)) || true
    if [[ -n "${TAP:-}" ]]; then
        echo "not ok $TESTS_RUN - $1"
        [[ -n "${2:-}" ]] && echo "#   $2"
    else
        echo -e "${RED}✗${NC} $1"
        [[ -n "${2:-}" ]] && echo "  $2"
    fi
}

run_test() {
    local name="$1"
    local func="$2"
    ((TESTS_RUN++)) || true
    if $func; then
        pass "$name"
    else
        fail "$name"
    fi
}

# --- Tests ---

test_help() {
    "$MD_AGE" -h | grep -q "Usage:"
}

test_encrypt_with_recipient_creates_frontmatter() {
    local output
    output=$(echo "Secret content" | "$MD_AGE" -e -r "$RECIPIENT")

    echo "$output" | grep -q "^---$" || return 1
    echo "$output" | grep -q "^age-encrypt: yes$" || return 1
    echo "$output" | grep -q "^age-recipients:$" || return 1
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1
}

test_encrypt_preserves_frontmatter() {
    cat > "$TMPDIR/input.md" << EOF
---
title: My Document
author: Test
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Secret body
EOF

    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")

    # Should preserve all frontmatter fields
    echo "$output" | grep -q "^title: My Document$" || return 1
    echo "$output" | grep -q "^author: Test$" || return 1
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1
}

test_decrypt_preserves_frontmatter() {
    # Create encrypted file
    cat > "$TMPDIR/input.md" << EOF
---
title: Secret Notes
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
The secret content
EOF

    "$MD_AGE" -e "$TMPDIR/input.md" > "$TMPDIR/encrypted.md"

    local output
    output=$("$MD_AGE" -d -i "$TESTKEY" "$TMPDIR/encrypted.md")

    echo "$output" | grep -q "^title: Secret Notes$" || return 1
    echo "$output" | grep -q "The secret content" || return 1
}

test_roundtrip() {
    local original="---
title: Roundtrip Test
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
# Heading

Body paragraph with special chars: <>&\"'"

    echo "$original" > "$TMPDIR/original.md"

    "$MD_AGE" -e "$TMPDIR/original.md" > "$TMPDIR/encrypted.md"
    "$MD_AGE" -d -i "$TESTKEY" "$TMPDIR/encrypted.md" > "$TMPDIR/decrypted.md"

    # Compare (normalize trailing whitespace)
    local orig_body dec_body
    orig_body=$(echo "$original" | sed -n '/^---$/,/^---$/!p' | sed '/^$/d')
    dec_body=$(cat "$TMPDIR/decrypted.md" | sed -n '/^---$/,/^---$/!p' | sed '/^$/d')

    [[ "$orig_body" == "$dec_body" ]]
}

test_output_file_option() {
    echo "Test content" | "$MD_AGE" -e -r "$RECIPIENT" -o "$TMPDIR/output.md"

    [[ -f "$TMPDIR/output.md" ]] || return 1
    grep -q "BEGIN AGE ENCRYPTED FILE" "$TMPDIR/output.md"
}

test_stdin_input() {
    local output
    output=$(echo "Stdin test" | "$MD_AGE" -e -r "$RECIPIENT")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_error_no_recipients() {
    local output
    if output=$(echo "No recipients" | "$MD_AGE" -e 2>&1); then
        return 1  # Should have failed
    fi
    echo "$output" | grep -qi "no recipients"
}

test_error_no_identity() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Secret
EOF
    "$MD_AGE" -e "$TMPDIR/input.md" > "$TMPDIR/encrypted.md"

    local output
    if output=$("$MD_AGE" -d "$TMPDIR/encrypted.md" 2>&1); then
        return 1  # Should have failed
    fi
    echo "$output" | grep -qi "no identity"
}

test_error_not_encrypted() {
    cat > "$TMPDIR/plain.md" << EOF
---
title: Plain file
---
Not encrypted
EOF

    local output
    if output=$("$MD_AGE" -d -i "$TESTKEY" "$TMPDIR/plain.md" 2>&1); then
        return 1  # Should have failed
    fi
    echo "$output" | grep -qi "no encrypted content"
}

test_error_file_not_found() {
    local output
    if output=$("$MD_AGE" -e "$TMPDIR/nonexistent.md" 2>&1); then
        return 1  # Should have failed
    fi
    echo "$output" | grep -qi "not found"
}

test_recipients_from_frontmatter() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Use frontmatter recipients
EOF

    # Should work without -r flag
    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

# Tests for flexible YAML parsing (issue: frontmatter parsing too strict)
test_recipients_no_indentation() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: yes
age-recipients:
- $RECIPIENT
---
Recipients without leading indentation
EOF

    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_age_encrypt_quoted() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: 'yes'
age-recipients:
  - $RECIPIENT
---
Single quoted yes
EOF

    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1

    cat > "$TMPDIR/input2.md" << EOF
---
age-encrypt: "yes"
age-recipients:
  - $RECIPIENT
---
Double quoted yes
EOF

    output=$("$MD_AGE" -e "$TMPDIR/input2.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_age_encrypt_true() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: true
age-recipients:
  - $RECIPIENT
---
Boolean true instead of yes
EOF

    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_age_encrypt_on() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: on
age-recipients:
  - $RECIPIENT
---
YAML on boolean
EOF

    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_age_encrypt_case_insensitive() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: YES
age-recipients:
  - $RECIPIENT
---
Uppercase YES
EOF

    local output
    output=$("$MD_AGE" -e "$TMPDIR/input.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1

    cat > "$TMPDIR/input2.md" << EOF
---
age-encrypt: True
age-recipients:
  - $RECIPIENT
---
Mixed case True
EOF

    output=$("$MD_AGE" -e "$TMPDIR/input2.md")
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_no_bash4_parameter_expansion() {
    # Regression: ${var,,} and ${var^^} require bash 4+ and fail on macOS bash 3.2
    # with "bad substitution". Ensure the script uses portable lowercase conversion.
    # Exclude comments (lines starting with optional whitespace then #).
    ! grep -v '^\s*#' "$MD_AGE" | grep -qE '\$\{[a-zA-Z_][a-zA-Z_0-9]*,,\}|\$\{[a-zA-Z_][a-zA-Z_0-9]*\^\^\}'
}

test_age_encrypt_unrecognized_warns() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: yess
age-recipients:
  - $RECIPIENT
---
Typo in age-encrypt value
EOF

    # Should fail and warn
    local output
    if output=$("$MD_AGE" -e "$TMPDIR/input.md" 2>&1); then
        # Should have failed
        return 1
    fi
    # Should contain warning about unrecognized value
    echo "$output" | grep -q "unrecognized age-encrypt value"
}

test_explicit_recipient_overrides_frontmatter() {
    # Create a second key
    local key2="$TMPDIR/key2.txt"
    age-keygen -o "$key2" 2>&1 | grep 'Public key:' | sed 's/Public key: //' > "$TMPDIR/recipient2.txt"
    local recipient2
    recipient2=$(cat "$TMPDIR/recipient2.txt")

    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Override test
EOF

    # Encrypt with different recipient
    "$MD_AGE" -e -r "$recipient2" "$TMPDIR/input.md" > "$TMPDIR/encrypted.md"

    # Should decrypt with key2, not original key
    "$MD_AGE" -d -i "$key2" "$TMPDIR/encrypted.md" | grep -q "Override test"
}

test_multiline_body() {
    cat > "$TMPDIR/input.md" << EOF
---
age-encrypt: yes
age-recipients:
  - $RECIPIENT
---
Line 1
Line 2

Line 4 after blank

# Heading

- List item 1
- List item 2
EOF

    "$MD_AGE" -e "$TMPDIR/input.md" > "$TMPDIR/encrypted.md"
    local output
    output=$("$MD_AGE" -d -i "$TESTKEY" "$TMPDIR/encrypted.md")

    echo "$output" | grep -q "Line 1" || return 1
    echo "$output" | grep -q "Line 4 after blank" || return 1
    echo "$output" | grep -q "List item 2" || return 1
}

test_git_help() {
    "$MD_AGE" git --help 2>&1 | grep -q "git subcommands"
}

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
    ! echo "$output" | grep -q "Secret content" || return 1
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

test_git_clean_preserves_trailing_newlines() {
    # Regression: bash $(cat) strips trailing newlines, making every .md file
    # appear modified in git worktrees. Compare via files to avoid the same
    # issue in the test harness itself.
    printf '# Just a readme\n\nSome content here.\n\n' > "$TMPDIR/trail_input.md"

    "$MD_AGE" git clean test.md < "$TMPDIR/trail_input.md" > "$TMPDIR/trail_output.md"

    # Output must be byte-identical to input
    local input_hash output_hash
    input_hash=$(shasum -a 256 < "$TMPDIR/trail_input.md" | cut -d' ' -f1)
    output_hash=$(shasum -a 256 < "$TMPDIR/trail_output.md" | cut -d' ' -f1)

    [[ "$input_hash" == "$output_hash" ]] || {
        echo "trailing newlines were stripped" >&2
        return 1
    }
}

test_git_smudge_preserves_trailing_newlines() {
    # Regression: same $(cat) issue in smudge filter
    printf '# Just a readme\n\nSome content here.\n\n' > "$TMPDIR/trail_input2.md"

    "$MD_AGE" git smudge test.md < "$TMPDIR/trail_input2.md" > "$TMPDIR/trail_output2.md"

    local input_hash output_hash
    input_hash=$(shasum -a 256 < "$TMPDIR/trail_input2.md" | cut -d' ' -f1)
    output_hash=$(shasum -a 256 < "$TMPDIR/trail_output2.md" | cut -d' ' -f1)

    [[ "$input_hash" == "$output_hash" ]] || {
        echo "trailing newlines were stripped" >&2
        return 1
    }
}

test_git_clean_worktree_shares_cache() {
    # Regression: worktrees had separate caches, causing encrypted files
    # to always appear modified due to non-deterministic age encryption
    local repo="$TMPDIR/worktree-cache-repo"
    git init -q "$repo"

    local cache_dir
    cache_dir=$(cd "$repo" && "$MD_AGE" git clean test.md </dev/null 2>/dev/null; git rev-parse --git-common-dir)/md-age/hashes

    # get_cache_dir should use --git-common-dir, not --git-dir
    local script_cache
    script_cache=$(cd "$repo" && git rev-parse --git-common-dir)/md-age/hashes

    [[ "$cache_dir" == "$script_cache" ]] || return 1

    # Verify --git-common-dir and --git-dir are same for non-worktree
    local common_dir git_dir
    common_dir=$(cd "$repo" && git rev-parse --git-common-dir)
    git_dir=$(cd "$repo" && git rev-parse --git-dir)
    [[ "$common_dir" == "$git_dir" ]] || return 1
}

test_git_integration_workflow() {
    local repo="$TMPDIR/integration-repo"
    git init -q "$repo"
    cd "$repo"

    # Add md-age to PATH so git filters can find it
    export PATH="$PROJECT_DIR/bin:$PATH"

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

# --- Directory encryption tests ---

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

test_git_dir_clean_ssh_key_with_comment() {
    # SSH keys in .age-recipients have spaces: "ssh-ed25519 AAAA... comment"
    # These must not get word-split when passed to age -r
    local repo="$TMPDIR/dir-clean-ssh"
    mkdir -p "$repo/secrets"
    git init -q "$repo"

    # Use a real-format SSH ed25519 public key with a comment
    # (age accepts any valid SSH public key as a recipient)
    local ssh_pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnfVKOiVFMNpfcEzwmFMJYNBHCnzMsp2DjXgGlFBEhI test-comment"
    echo "$ssh_pubkey" > "$repo/.age-recipients"

    local output
    output=$(cd "$repo" && echo 'secret data' | "$MD_AGE" git dir-clean secrets/file.txt)

    # Should succeed and produce encrypted envelope
    echo "$output" | grep -q "^age-encrypt: yes$" || return 1
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1
    ! echo "$output" | grep -q 'secret data' || return 1
}

test_git_dir_clean_walks_up() {
    # .age-recipients at repo root, file in subdirectory
    local repo="$TMPDIR/dir-clean-walkup"
    mkdir -p "$repo/secrets/nested"
    git init -q "$repo"
    echo "$RECIPIENT" > "$repo/.age-recipients"

    local output
    output=$(cd "$repo" && echo "nested data" | "$MD_AGE" git dir-clean secrets/nested/file.txt)
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE"
}

test_git_dir_clean_nearest_recipients_wins() {
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

test_git_dir_clean_stops_at_git_root() {
    # .age-recipients above git root should not be found
    local dir="$TMPDIR/dir-clean-root"
    mkdir -p "$dir/repo/secrets"
    echo "$RECIPIENT" > "$dir/.age-recipients"
    git init -q "$dir/repo"

    if echo "data" | (cd "$dir/repo" && "$MD_AGE" git dir-clean secrets/file.txt) 2>/dev/null; then
        return 1  # Should have failed
    fi
    return 0
}

test_git_dir_clean_strips_comments() {
    local repo="$TMPDIR/dir-clean-comments"
    mkdir -p "$repo/secrets"
    git init -q "$repo"

    cat > "$repo/.age-recipients" << EOF
# This is a comment
$RECIPIENT

# Another comment
EOF

    local output
    output=$(cd "$repo" && echo "data" | "$MD_AGE" git dir-clean secrets/file.txt)
    echo "$output" | grep -q "BEGIN AGE ENCRYPTED FILE" || return 1
    # Comments should not appear in envelope
    ! echo "$output" | grep -q "# This is a comment" || return 1
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

test_git_dir_clean_envelope_compat() {
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

test_git_add_dir_creates_marker() {
    local repo="$TMPDIR/add-dir-repo"
    git init -q "$repo"
    mkdir -p "$repo/secrets"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) >/dev/null || return 1

    [[ -f "$repo/secrets/.age-encrypt" ]]
}

test_git_add_dir_updates_gitattributes() {
    local repo="$TMPDIR/add-dir-attr"
    git init -q "$repo"
    mkdir -p "$repo/secrets"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) >/dev/null || return 1

    grep -q 'secrets/\*\* filter=md-age-dir diff=md-age-dir' "$repo/.gitattributes" || return 1
    grep -q 'secrets/.age-encrypt !filter !diff' "$repo/.gitattributes" || return 1
}

test_git_add_dir_idempotent() {
    local repo="$TMPDIR/add-dir-idem"
    git init -q "$repo"
    mkdir -p "$repo/secrets"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) >/dev/null || return 1
    (cd "$repo" && "$MD_AGE" git add-dir secrets) >/dev/null || return 1

    # Should only have one entry, not duplicates
    local count
    count=$(grep -c 'secrets/\*\* filter=md-age-dir' "$repo/.gitattributes")
    [[ "$count" -eq 1 ]]
}

test_git_add_dir_multiple_dirs() {
    local repo="$TMPDIR/add-dir-multi"
    git init -q "$repo"
    mkdir -p "$repo/secrets" "$repo/credentials"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) >/dev/null || return 1
    (cd "$repo" && "$MD_AGE" git add-dir credentials) >/dev/null || return 1

    grep -q 'secrets/\*\* filter=md-age-dir' "$repo/.gitattributes" || return 1
    grep -q 'credentials/\*\* filter=md-age-dir' "$repo/.gitattributes" || return 1
    [[ -f "$repo/secrets/.age-encrypt" ]] || return 1
    [[ -f "$repo/credentials/.age-encrypt" ]]
}

test_git_add_dir_creates_dir_if_missing() {
    local repo="$TMPDIR/add-dir-mkdir"
    git init -q "$repo"

    (cd "$repo" && "$MD_AGE" git add-dir newdir) >/dev/null || return 1

    [[ -d "$repo/newdir" ]] || return 1
    [[ -f "$repo/newdir/.age-encrypt" ]]
}

test_git_add_dir_relative_dot() {
    local repo="$TMPDIR/add-dir-dot"
    git init -q "$repo"
    mkdir -p "$repo/editorial/inbox/2026-02-13"

    # Run add-dir . from inside a subdirectory
    (cd "$repo/editorial/inbox/2026-02-13" && "$MD_AGE" git add-dir .) >/dev/null || return 1

    # .age-encrypt should be in the subdirectory, not the repo root
    [[ -f "$repo/editorial/inbox/2026-02-13/.age-encrypt" ]] || return 1
    [[ ! -f "$repo/.age-encrypt" ]] || return 1

    # .gitattributes should reference the full path, not "."
    grep -q "editorial/inbox/2026-02-13/\*\*" "$repo/.gitattributes" || return 1
    ! grep -q '^\./\*\*' "$repo/.gitattributes"
}

test_git_add_dir_relative_dotdot() {
    local repo="$TMPDIR/add-dir-dotdot"
    git init -q "$repo"
    mkdir -p "$repo/a/b" "$repo/a/target"

    # Run add-dir ../target from a/b
    (cd "$repo/a/b" && "$MD_AGE" git add-dir ../target) >/dev/null || return 1

    [[ -f "$repo/a/target/.age-encrypt" ]] || return 1
    grep -q "a/target/\*\*" "$repo/.gitattributes" || return 1
}

test_git_add_dir_excludes_local_recipients() {
    local repo="$TMPDIR/add-dir-local-recip"
    git init -q "$repo"
    mkdir -p "$repo/secrets"
    echo "$RECIPIENT" > "$repo/secrets/.age-recipients"

    (cd "$repo" && "$MD_AGE" git add-dir secrets) >/dev/null || return 1

    grep -q 'secrets/.age-recipients !filter !diff' "$repo/.gitattributes"
}

test_git_init_registers_dir_filter() {
    local repo="$TMPDIR/init-dir-filter"
    git init -q "$repo"

    (cd "$repo" && "$MD_AGE" git init) >/dev/null || return 1

    (cd "$repo" && git config --get filter.md-age-dir.clean) | grep -q "dir-clean" || return 1
    (cd "$repo" && git config --get filter.md-age-dir.smudge) | grep -q "dir-smudge" || return 1
    (cd "$repo" && git config --get filter.md-age-dir.required) | grep -q "true" || return 1
    (cd "$repo" && git config --get diff.md-age-dir.textconv) | grep -q "dir-smudge" || return 1
}

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

# --- Main ---

main() {
    if [[ -z "${TAP:-}" ]]; then
        echo "Testing bin/md-age"
        echo "=================="
        echo ""
    fi

    setup
    trap teardown EXIT

    run_test "shows help" test_help
    run_test "encrypt with -r creates frontmatter" test_encrypt_with_recipient_creates_frontmatter
    run_test "encrypt preserves existing frontmatter" test_encrypt_preserves_frontmatter
    run_test "decrypt preserves frontmatter" test_decrypt_preserves_frontmatter
    run_test "roundtrip encrypt/decrypt" test_roundtrip
    run_test "-o writes to output file" test_output_file_option
    run_test "reads from stdin" test_stdin_input
    run_test "uses recipients from frontmatter" test_recipients_from_frontmatter
    run_test "recipients without leading indentation" test_recipients_no_indentation
    run_test "age-encrypt with quoted yes" test_age_encrypt_quoted
    run_test "age-encrypt: true" test_age_encrypt_true
    run_test "age-encrypt: on" test_age_encrypt_on
    run_test "age-encrypt case insensitive" test_age_encrypt_case_insensitive
    run_test "no bash 4+ parameter expansion" test_no_bash4_parameter_expansion
    run_test "age-encrypt unrecognized value warns" test_age_encrypt_unrecognized_warns
    run_test "explicit -r overrides frontmatter recipients" test_explicit_recipient_overrides_frontmatter
    run_test "handles multiline body" test_multiline_body
    run_test "error: no recipients specified" test_error_no_recipients
    run_test "error: no identity for decrypt" test_error_no_identity
    run_test "error: file not encrypted" test_error_not_encrypted
    run_test "error: file not found" test_error_file_not_found
    run_test "git subcommand shows help" test_git_help
    run_test "git init sets up filters" test_git_init
    run_test "git config add adds identity" test_git_config_add
    run_test "git config list shows identities" test_git_config_list
    run_test "git config supports multiple identities" test_git_config_multiple_identities
    run_test "git clean passes through non-md-age files" test_git_clean_passthrough
    run_test "git clean encrypts md-age files" test_git_clean_encrypts
    run_test "git clean fails without recipients" test_git_clean_fails_no_recipients
    run_test "git smudge passes through non-md-age files" test_git_smudge_passthrough_plain
    run_test "git smudge passes through when no identity" test_git_smudge_passthrough_no_identity
    run_test "git smudge decrypts with identity" test_git_smudge_decrypts
    run_test "git clean is deterministic with caching" test_git_clean_deterministic
    run_test "git clean cache invalidates on content change" test_git_clean_cache_invalidates_on_change
    run_test "git clean preserves trailing newlines" test_git_clean_preserves_trailing_newlines
    run_test "git smudge preserves trailing newlines" test_git_smudge_preserves_trailing_newlines
    run_test "git clean cache uses git-common-dir for worktrees" test_git_clean_worktree_shares_cache
    run_test "git integration: add/commit/checkout workflow" test_git_integration_workflow

    # Directory encryption tests
    run_test "dir-clean encrypts with envelope" test_git_dir_clean_encrypts
    run_test "dir-clean handles SSH keys with comments" test_git_dir_clean_ssh_key_with_comment
    run_test "dir-clean walks up for .age-recipients" test_git_dir_clean_walks_up
    run_test "dir-clean nearest .age-recipients wins" test_git_dir_clean_nearest_recipients_wins
    run_test "dir-clean fails without .age-recipients" test_git_dir_clean_fails_no_recipients_file
    run_test "dir-clean stops at git root" test_git_dir_clean_stops_at_git_root
    run_test "dir-clean strips comments from .age-recipients" test_git_dir_clean_strips_comments
    run_test "dir-clean is deterministic with caching" test_git_dir_clean_deterministic
    run_test "dir-clean envelope compatible with md-age -d" test_git_dir_clean_envelope_compat
    run_test "dir-smudge decrypts to raw content" test_git_dir_smudge_decrypts
    run_test "dir-smudge strips envelope" test_git_dir_smudge_strips_envelope
    run_test "dir-smudge passes through without identity" test_git_dir_smudge_passthrough_no_identity
    run_test "dir-smudge passes through non-envelope" test_git_dir_smudge_passthrough_no_envelope
    run_test "add-dir creates .age-encrypt marker" test_git_add_dir_creates_marker
    run_test "add-dir updates .gitattributes" test_git_add_dir_updates_gitattributes
    run_test "add-dir is idempotent" test_git_add_dir_idempotent
    run_test "add-dir handles multiple directories" test_git_add_dir_multiple_dirs
    run_test "add-dir creates directory if missing" test_git_add_dir_creates_dir_if_missing
    run_test "add-dir normalizes . from subdirectory" test_git_add_dir_relative_dot
    run_test "add-dir normalizes ../relative paths" test_git_add_dir_relative_dotdot
    run_test "add-dir excludes local .age-recipients" test_git_add_dir_excludes_local_recipients
    run_test "git init registers md-age-dir filter" test_git_init_registers_dir_filter
    run_test "dir integration: add/commit/checkout workflow" test_git_dir_integration_workflow
    run_test "dir integration: binary file roundtrip" test_git_dir_binary_roundtrip

    if [[ -n "${TAP:-}" ]]; then
        echo "1..$TESTS_RUN"
    else
        echo ""
        echo "=================="
        echo "Tests: $TESTS_RUN  Passed: $TESTS_PASSED  Failed: $TESTS_FAILED"
    fi

    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
