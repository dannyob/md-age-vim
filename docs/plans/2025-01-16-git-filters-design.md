# Git Filters for md-age

Design for transparent age encryption via git smudge/clean filters.

## Overview

Add `md-age git` subcommands that serve as git filters. Files encrypt on stage (clean), decrypt on checkout (smudge). Hash caching handles non-deterministic encryption.

## Commands

```
md-age git smudge           # Decrypt filter (stdin → stdout)
md-age git clean            # Encrypt filter (stdin → stdout)
md-age git config add -i    # Add identity to git config
md-age git config list      # Show configured identities
md-age git config remove -i # Remove identity from git config
md-age git init             # Set up filters in current repo
```

## Git Configuration

After `md-age git init`, `.git/config` contains:

```ini
[md-age "config"]
    identity = ~/.age/key.txt

[filter "md-age"]
    required = true
    smudge = md-age git smudge %f
    clean = md-age git clean %f

[diff "md-age"]
    textconv = md-age git smudge
```

User adds to `.gitattributes` (version controlled):

```
*.md filter=md-age diff=md-age
```

## Clean Filter (Encrypt on Stage)

Invoked by `git add`, `git commit`.

1. Read stdin, parse frontmatter
2. If no `age-encrypt: yes` → pass through unchanged
3. Extract recipients from frontmatter
4. If no recipients → exit 1 (hard fail)
5. Compute cache key: `SHA256(sorted_recipients || "\x00" || plaintext_body)`
6. Check cache `.git/md-age/hashes/<key>`
   - Hit → use cached ciphertext
   - Miss → encrypt with `age -e -a`, cache result
7. Output frontmatter + ciphertext

Hard fails on: missing recipients, `age` not found, encryption error, missing recipient file.

## Smudge Filter (Decrypt on Checkout)

Invoked by `git checkout`, `git clone`.

1. Read stdin, parse frontmatter
2. If no `age-encrypt: yes` → pass through unchanged
3. If body not encrypted → pass through unchanged
4. Get identities from git config
5. If no identity → pass through encrypted (silent)
6. Attempt decrypt with `age -d -i <identity>`
   - Success → output frontmatter + plaintext
   - Failure → pass through encrypted (silent)

Never hard-fails. Allows clones without identity configured.

## Hash Caching

Prevents spurious "modified" status from non-deterministic encryption.

Location: `.git/md-age/hashes/<first-2>/<full-hash>`

Cache key includes recipients, so changing recipients forces re-encryption.

No explicit invalidation needed — content-addressed cache. Old entries become orphans.

## User Workflow

Initial setup:
```bash
md-age git init
md-age git config add -i ~/.age/key.txt
echo '*.md filter=md-age diff=md-age' >> .gitattributes
git add .gitattributes && git commit -m "Enable md-age filtering"
```

Daily use is transparent — vim plugin shows plaintext, git stores ciphertext.

Fresh clone:
```bash
git clone repo && cd repo
md-age git config add -i ~/.age/key.txt
git checkout .  # Re-trigger smudge
```

CI (no identity): files stay encrypted, clone succeeds.
