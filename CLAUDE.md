# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make test      # Run all tests (auto-clones vim-testify to deps/)
make clean     # Remove deps/ and testify_results.txt
```

Run a single test file:
```bash
nvim --headless \
  -c "set rtp+=deps/vim-testify" \
  -c "set rtp+=." \
  -c "runtime plugin/testify.vim" \
  -c "runtime plugin/md-age.vim" \
  -c "TestifyFile t/frontmatter_test.vim"
```

## Architecture

md-age-vim provides transparent age encryption for markdown files. It encrypts only the body while preserving YAML frontmatter as plaintext.

### File Structure

- `plugin/md-age.vim` - Autocommands (BufReadPost/BufWritePre/BufWritePost for *.md) and command definitions
- `autoload/mdage.vim` - Core functions: parsing, encryption, decryption
- `t/` - Tests using vim-testify

### Encryption Flow

**On open (BufReadPost):** Parse frontmatter → check `age-encrypt: yes` → decrypt armored body using `g:md_age_identity` → replace in buffer

**On save (BufWritePre):** Get recipients from frontmatter → encrypt body → write frontmatter + ciphertext

**After save (BufWritePost):** Restore plaintext to buffer so user can keep editing

### Key Functions in autoload/mdage.vim

- `mdage#ParseFrontmatter(lines)` - Returns `{fields: {}, end_line: N}`
- `mdage#GetRecipients(parsed, lines)` - Extracts recipient list from YAML array
- `mdage#BuildRecipientArgs(recipients)` - Converts to `-r`/`-R` CLI args
- `mdage#Encrypt(plaintext, recipients)` / `mdage#Decrypt(ciphertext, identity_args)`
- `mdage#Init()` - Inserts frontmatter template

### Recipient Types

- `age1...` → `-r` (age public key)
- `ssh-...` → `-r` (SSH public key)
- Anything else → `-R` (file path)

### Configuration Variables

- `g:md_age_identity` (required) - CLI args for age identity, e.g., `-i ~/.age/key.txt`
- `g:md_age_command` (optional) - age binary, default `'age'`
- `g:md_age_default_recipients` (optional) - string or list for `:MdAgeInit` template
