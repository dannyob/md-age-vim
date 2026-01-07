# md-age-vim Design

A vim plugin for transparent age encryption of markdown files.

## Overview

md-age-vim encrypts and decrypts markdown files transparently, similar to gpg.vim but using age encryption. It activates on markdown files that have specific frontmatter fields, encrypting only the body while preserving the frontmatter as plaintext.

## Activation

The plugin hooks into `BufReadPost` and `BufWritePre` for `*.md` files. On load, it parses YAML frontmatter looking for:

```yaml
---
title: My Document
age-encrypt: yes
age-recipients:
  - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  - ~/.age/work-recipients.txt
  - ssh-ed25519 AAAA...
---
```

Behavior:
- `age-encrypt: yes` + valid recipients: decrypt on load, encrypt on save
- `age-encrypt:` missing or not `yes`: normal markdown file, no encryption
- `age-encrypt: yes` but no `age-recipients:`: error on save, refuse to encrypt

All frontmatter is preserved exactly as-is (never encrypted). Only content after the closing `---` gets encrypted/decrypted.

## Configuration

### Required

```vim
let g:md_age_identity = '-i ~/.age/identity.txt'
```

This is passed directly to age as command-line arguments. Examples:
- `-i ~/.age/key.txt` - simple identity file
- `-j` - use age plugins (yubikey, etc.)
- `-i ~/.age/personal.txt -i ~/.age/work.txt` - multiple identities

### Optional

```vim
let g:md_age_command = 'rage'  " default: 'age'
```

## File Format

### On disk (encrypted)

```markdown
---
title: Secret Project Notes
date: 2025-01-07
age-encrypt: yes
age-recipients:
  - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
---
-----BEGIN AGE ENCRYPTED FILE-----
YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBHMnVSV2xGTmdwSXVQSXhu
...
-----END AGE ENCRYPTED FILE-----
```

### In buffer (decrypted)

```markdown
---
title: Secret Project Notes
date: 2025-01-07
age-encrypt: yes
age-recipients:
  - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
---
# My Secret Notes

This is the plaintext content the user edits.
```

## Commands

- `:MdAgeInit` - Insert frontmatter template at top of buffer
- `:MdAgeStatus` - Show current encryption state (encrypted/decrypted/not-encrypted-file)

## Implementation Structure

```
plugin/md-age.vim      # Auto-commands, command definitions
autoload/mdage.vim     # Core functions (parse, encrypt, decrypt)
doc/md-age.txt         # Vim help file
t/                     # Tests (vim-testify)
  frontmatter_test.vim
  recipients_test.vim
  encrypt_test.vim
```

## Testing

Uses [vim-testify](https://github.com/dhruvasagar/vim-testify) for TDD.

```vim
function! s:TestParseFrontmatter()
  let lines = ['---', 'age-encrypt: yes', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  call testify#assert#equals(result.age_encrypt, 'yes')
  call testify#assert#equals(result.body_start, 4)
endfunction
call testify#it('parses frontmatter', function('s:TestParseFrontmatter'))
```

Run tests with `:TestifySuite` or `vim -c 'TestifySuite' -c 'qa!'`

### Key functions

- `mdage#ParseFrontmatter()` - Extract YAML frontmatter, return dict
- `mdage#ShouldEncrypt()` - Check for `age-encrypt: yes`
- `mdage#GetRecipients()` - Parse recipient list, expand file paths
- `mdage#Decrypt()` - Called on `BufReadPost`, decrypt body if needed
- `mdage#Encrypt()` - Called on `BufWritePre`, encrypt body before write
- `mdage#RestoreBuffer()` - Called on `BufWritePost`, restore plaintext to buffer

Pure vimscript for vim/neovim compatibility. Uses `system()` for shell calls.

## Encrypt/Decrypt Flow

### On file open (`BufReadPost *.md`)

1. Parse frontmatter, check `age-encrypt: yes`
2. If not encrypted file: do nothing
3. Check `g:md_age_identity` is set: error if not
4. Extract armored ciphertext (everything after frontmatter)
5. Run: `echo {ciphertext} | {g:md_age_command} -d {g:md_age_identity}`
6. On success: replace ciphertext with plaintext in buffer, set `b:md_age_encrypted = 1`
7. On failure: set buffer read-only, show error

### On file save (`BufWritePre *.md`)

1. Check `b:md_age_encrypted` or parse frontmatter for `age-encrypt: yes`
2. If not encrypted file: do nothing
3. Check recipients exist: error if missing
4. Build recipient args: `-r age1... -R ~/.age/file.txt -r ssh-ed25519...`
5. Run: `echo {plaintext} | {g:md_age_command} -e -a {recipient_args}`
6. Replace buffer content with frontmatter + armored ciphertext
7. Let vim write the file

### After save (`BufWritePost *.md`)

1. If `b:md_age_encrypted`: restore plaintext to buffer so user can keep editing

## Edge Cases

- **No frontmatter at all**: treat as normal file, no encryption
- **Frontmatter but no `age-encrypt:`**: normal file
- **`age-encrypt: no`**: explicitly disabled, treat as normal file
- **Empty body**: valid, encrypt empty string
- **File has armored block but `age-encrypt:` missing**: treat as normal file
- **Multiple `---` in body**: only first two `---` are frontmatter delimiters

## Recipient Parsing

- Starts with `age1`: raw public key, use `-r`
- Starts with `ssh-`: SSH public key, use `-r`
- Otherwise: treat as file path, expand `~`, use `-R`

## Error Handling

- `g:md_age_identity` not set: error on decrypt attempt
- Decryption fails: set buffer read-only with ciphertext visible, show error
- No recipients in frontmatter: error on save attempt
- Encryption fails: passthrough age's stderr

### Error Messages

- `"md-age: g:md_age_identity not set"`
- `"md-age: decryption failed - buffer set read-only"`
- `"md-age: no recipients in frontmatter"`
- `"md-age: encryption failed: {age stderr}"`

## Passphrase Handling

Shell passthrough - age handles its own prompts via TTY. This allows support for age plugins (yubikey, etc.) that have their own prompt mechanisms.
