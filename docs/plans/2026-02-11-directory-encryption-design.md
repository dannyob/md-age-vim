# Directory Encryption for md-age

Design for transparent age encryption of entire directories via git clean/smudge filters.

## Problem

md-age currently encrypts individual markdown files: plaintext frontmatter + encrypted body. This works well for notes and documents. But sometimes you want to encrypt a whole directory of arbitrary files (configs, keys, assets) and store them in a git repo where they appear as normal editable files in the working tree but are encrypted in git.

## Approach

Extend the existing `md-age git clean/smudge` filters to handle non-markdown files. Each file in a designated directory gets individually encrypted, wrapped in an md-age frontmatter envelope. The working tree has raw files; git stores envelope-wrapped ciphertext.

```
Working tree (plaintext)         Git blob (encrypted)
========================         ====================

secrets/config.json         →    ---
{ "api_key": "abc123" }          age-encrypt: yes
                                 age-recipients:
                                   - age1abc...
                                 ---
                                 -----BEGIN AGE ENCRYPTED FILE-----
                                 ...
                                 -----END AGE ENCRYPTED FILE-----

secrets/cert.pem            →    (same envelope format)
-----BEGIN CERTIFICATE-----
...
```

### Why per-file, not tar archive

- Git tracks individual file changes (add, remove, rename)
- Merges and diffs work at file granularity
- Only changed files re-encrypt on commit
- Compatible with existing md-age tooling (vim plugin, `md-age -d`, `md-age git rekey`)

### What's visible in git

- Directory structure and filenames: **yes** (visible)
- File contents: **no** (encrypted)
- Recipients: **yes** (in each file's frontmatter)

If hiding filenames and structure is required, the tar-archive approach (single encrypted blob containing a tarball) is better, but that requires hooks rather than clean/smudge and loses per-file git history. Out of scope for this design.

## Encryption Trigger and Recipient Discovery

Two separate concerns, two separate files:

### .age-encrypt (trigger)

An empty file whose presence marks a directory for encryption. Create it with `touch secrets/.age-encrypt`.

This is analogous to `age-encrypt: yes` in markdown frontmatter. The clean filter checks for this file before doing anything. No `.age-encrypt`, no encryption — the filter passes content through unchanged.

The `.age-encrypt` file is checked into git (so cloners know which directories are encrypted) but is itself excluded from the encryption filter via `.gitattributes`.

### .age-recipients (recipient list)

A file containing one recipient per line, same format as frontmatter `age-recipients`:

```
# .age-recipients (at repo root, or any ancestor directory)
age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...
git:assets/keys/editors
```

Comments (lines starting with `#`) and blank lines are ignored.

**Walk-up resolution:** The clean filter searches for `.age-recipients` starting from the file's directory and walking up through ancestors, stopping at the git repository root. The nearest `.age-recipients` wins.

This means the common case — all encrypted directories share the same recipients — requires just one `.age-recipients` at the repo root. A specific directory can override by placing its own `.age-recipients` closer.

```
repo/
├── .age-recipients          ← default for everything
├── .gitattributes
├── secrets/
│   ├── .age-encrypt         ← trigger: encrypt this directory
│   └── config.json
├── credentials/
│   ├── .age-encrypt         ← trigger: encrypt this too
│   ├── .age-recipients      ← override: different recipients
│   └── prod.env
└── docs/
    └── readme.md            ← no .age-encrypt, not encrypted
```

### Why separate them

Combining trigger and recipients in one file (the earlier `.age-recipients`-as-trigger design) prevents the most common case: multiple encrypted directories sharing the same recipient list. Separating them means:

- **One `.age-recipients` at the repo root** covers all encrypted directories
- **`touch dir/.age-encrypt`** is all it takes to add a new encrypted directory
- No symlinks needed for the common case (though they still work if you want per-directory recipient overrides pointing elsewhere)
- The trigger (which directories?) and the policy (encrypted to whom?) are independently manageable

### Recipients are always read from .age-recipients

The clean filter always reads recipients from the nearest `.age-recipients` file, every time it runs. There is no per-file recipient persistence — no reading from previously committed envelopes via `git show HEAD:<path>`.

This is simpler, faster (no git subprocess per file), and avoids edge cases (first commit, renames, rebases, worktrees). The `.age-recipients` file on disk is the single source of truth. No hidden state.

Changing `.age-recipients` takes effect for any file that passes through the clean filter (i.e., any file you `git add`). Files you don't touch keep their old ciphertext in git. Run `md-age git rekey` to re-encrypt everything with updated recipients.

## Filter Design

### New filter: `md-age-dir`

A separate filter from `md-age`, because the contract is different:

- `md-age` filter: checks frontmatter for `age-encrypt: yes`, passes through if absent
- `md-age-dir` filter: encrypts unconditionally (presence of `.age-encrypt` in directory is the trigger, enforced by `.gitattributes` scope), reads recipients from `.age-recipients` walk-up

```ini
# .git/config (set up by md-age git init)
[filter "md-age-dir"]
    clean = md-age git dir-clean %f
    smudge = md-age git dir-smudge %f
    required = true

[diff "md-age-dir"]
    textconv = sh -c 'cat "$1" | md-age git dir-smudge "$1"' --
```

```
# .gitattributes
secrets/** filter=md-age-dir diff=md-age-dir
secrets/.age-encrypt !filter !diff
credentials/** filter=md-age-dir diff=md-age-dir
credentials/.age-encrypt !filter !diff
credentials/.age-recipients !filter !diff
```

### dir-clean (encrypt on stage)

Input: raw file content from stdin, filename as `%f`

1. Walk up from file's directory looking for `.age-recipients` (stop at git root). If not found, error.
2. Read recipients from the `.age-recipients` file found.
3. Compute cache key: `SHA256(resolved_recipients || NUL || raw_content)`.
4. Check hash cache — if hit, use cached ciphertext.
5. Encrypt the raw content with `age -e -a`.
6. Store ciphertext in hash cache.
7. Wrap in frontmatter envelope and output:
   ```
   ---
   age-encrypt: yes
   age-recipients:
     - age1abc...
   ---
   <age armor>
   ```

The envelope is minimal — just `age-encrypt` and `age-recipients`. No content-type or other metadata; the filename already tells you what the file is, and the smudge filter strips the envelope regardless.

Recipients are written into each file's envelope so the encrypted blob is self-describing — you can decrypt it with `md-age -d` without needing the `.age-recipients` file.

### dir-smudge (decrypt on checkout)

Input: envelope-wrapped ciphertext from stdin, filename as `%f`

1. Parse frontmatter. If no frontmatter or no `age-encrypt: yes`, pass through unchanged.
2. Get identities from `git config md-age.config.identity` (same as existing smudge).
3. If no identity configured, pass through unchanged (allows cloning without keys).
4. Decrypt the age armor.
5. Output raw decrypted content (strip the envelope entirely).

Never hard-fails. Allows clones without identity configured.

### Rekey

`md-age git rekey secrets/` re-stages files through the clean filter. Since the clean filter always reads from `.age-recipients`, rekey naturally picks up any recipient changes. No special handling needed beyond what exists today.

## Setup Workflow

```bash
# One-time repo setup
md-age git init                          # sets up md-age and md-age-dir filters
md-age git config add -i ~/.age/key.txt  # add decryption identity

# Add recipients (once, at repo root)
cat > .age-recipients << 'EOF'
age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
EOF
git add .age-recipients

# Create an encrypted directory (helper command)
md-age git add-dir secrets/
# → creates secrets/.age-encrypt
# → appends to .gitattributes:
#     secrets/** filter=md-age-dir diff=md-age-dir
#     secrets/.age-encrypt !filter !diff

# Use normally
echo '{"api_key": "abc123"}' > secrets/config.json
git add .gitattributes secrets/
git commit -m "Add encrypted secrets directory"

# Verify: git stores ciphertext, working tree has plaintext
git show HEAD:secrets/config.json | head -5
# ---
# age-encrypt: yes
# ...
# ---
# -----BEGIN AGE ENCRYPTED FILE-----

cat secrets/config.json
# {"api_key": "abc123"}
```

Adding more encrypted directories is just:

```bash
md-age git add-dir credentials/
md-age git add-dir keys/
# all use the same .age-recipients at repo root
```

Fresh clone:

```bash
git clone repo && cd repo
md-age git config add -i ~/.age/key.txt
git checkout .   # re-trigger smudge
ls secrets/      # plaintext files
```

## Compatibility

### LFS

Git LFS uses clean/smudge filters. Since git only allows one filter per path, chaining requires a composite filter command:

```ini
[filter "md-age-dir-lfs"]
    clean = md-age git dir-clean %f | git lfs clean -- %f
    smudge = git lfs smudge -- %f | md-age git dir-smudge %f
    required = true
```

This composes naturally: clean encrypts then hands to LFS (which stores the blob remotely, outputs a pointer). Smudge fetches from LFS then decrypts.

LFS is a good fit here because encrypted blobs don't delta-compress well in git packfiles — age's nondeterministic encryption produces entirely different output for a one-byte plaintext change. The hash cache mitigates this for unchanged files (same plaintext = same cached ciphertext = same LFS OID), but changed files always produce new blobs. LFS keeps those out of the repo's packfile history.

Custom LFS backends (e.g., git-lfs-ipfs) work the same way — they replace the transfer layer, not the filter layer. The pipe composition is transparent to the backend.

### Existing md-age markdown filter

The `md-age` and `md-age-dir` filters coexist. A repo can use both:

```
*.md filter=md-age diff=md-age
secrets/** filter=md-age-dir diff=md-age-dir
secrets/.age-encrypt !filter !diff
```

Markdown files in `secrets/` would match `md-age-dir` (more specific glob wins in `.gitattributes`). If you want some `.md` files in `secrets/` to use the regular md-age flow (with their own frontmatter recipients), you'd need an explicit override line.

### Vim plugin

The vim plugin operates on buffer content, not git blobs. It won't interact with directory-encrypted files directly — those files appear as raw plaintext in the working tree (no frontmatter, no encryption visible to vim). The plugin continues to work normally for regular md-age markdown files.

## Security Model

The trust model is the same as existing md-age and tools like git-crypt/sops:

- Anyone with push access to the repo can modify `.age-recipients`
- Changing `.age-recipients` takes effect on next `git add` of affected files
- An attacker with push access could add themselves as a recipient, but they could also push plaintext directly — push access is the trust boundary
- Rekey after recipient changes produces a visible, auditable commit
- File content is confidential; filenames and directory structure are not

## Decisions

- **Setup**: `md-age git add-dir <path>` helper command creates `.age-encrypt` and appends `.gitattributes` entries. Explicit, composable, no magic scanning.
- **Envelope format**: minimal — just `age-encrypt: yes` and `age-recipients`. No `age-content-type` or other metadata. The filename already identifies the content; extra fields add maintenance cost for no benefit.
- **Walk-up `.age-recipients` scope**: directory encryption only. Regular md-age markdown files still require `age-recipients` in their own frontmatter. The two flows stay independent for now — unifying them is a possible future enhancement but would change existing behavior.

## Future Considerations

- **Commit hook for `.age-recipients` validation**: a pre-commit hook could warn if `.age-encrypt` exists in a directory but no `.age-recipients` is reachable. Out of scope for initial implementation.
- **Encrypted frontmatter**: a future `encrypt-subsequent-frontmatter` feature for md-age markdown files would encrypt metadata fields beyond the recipients. The directory encryption envelope is compatible with this — the envelope uses only the standard `age-encrypt` and `age-recipients` fields, leaving room for additional fields that could be encrypted in a future format revision.
