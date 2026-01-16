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
