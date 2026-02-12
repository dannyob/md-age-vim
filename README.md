# md-age-vim

Transparent [age](https://age-encryption.org/) encryption for markdown files in Vim/Neovim.

## Features

- Automatic decryption when opening markdown files
- Automatic encryption when saving
- Preserves all YAML frontmatter (not just age fields)
- ASCII-armored output for git-friendliness
- Supports age public keys, SSH keys, and recipient files

## Installation

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'dannyob/md-age-vim'
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'dannyob/md-age-vim' }
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use 'dannyob/md-age-vim'
```

Using native vim packages:

```bash
git clone https://github.com/dannyob/md-age-vim ~/.vim/pack/plugins/start/md-age-vim
```

Using native neovim packages:

```bash
git clone https://github.com/dannyob/md-age-vim ~/.local/share/nvim/site/pack/plugins/start/md-age-vim
```

## Configuration

Required - set your identity:

```vim
let g:md_age_identity = '-i ~/.age/identity.txt'
```

Optional - use a different age command:

```vim
let g:md_age_command = 'rage'
```

Optional - set default recipients for `:MdAgeInit`:

```vim
" Single recipient
let g:md_age_default_recipients = 'age1example7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

" Multiple recipients
let g:md_age_default_recipients = [
  \ 'age1example7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  \ '~/.age/backup.pub'
  \ ]
```

## Usage

Add frontmatter to your markdown file:

```yaml
---
title: My Secret Notes
age-encrypt: yes
age-recipients:
  - age1example7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
---
```

Or use `:MdAgeInit` to insert a template.

The file will be automatically decrypted when opened and encrypted when saved.

## Vim Commands

- `:MdAgeInit` - Insert frontmatter template
- `:MdAgeStatus` - Show encryption status

## Command-Line Tool

A standalone `md-age` script is included in `bin/` for shell usage:

```bash
# Encrypt using recipients from frontmatter
md-age -e notes.md > notes.md.enc

# Encrypt with explicit recipient (creates frontmatter)
md-age -e -r age1... plaintext.md > encrypted.md

# Decrypt
md-age -d -i ~/.age/key.txt encrypted.md > decrypted.md

# See all options
md-age -h
```

## Git Integration

Transparent encryption in git repositories using smudge/clean filters.

### Setup

1. Initialize filters in your repository (also creates `.gitattributes`):

```bash
md-age git init
```

2. Add your identity (for decryption):

```bash
md-age git config add -i ~/.age/key.txt
```

3. Commit `.gitattributes` so other clones use the filter.

### How It Works

- **On commit:** The clean filter encrypts md-age files before storing in git
- **On checkout:** The smudge filter decrypts files in your working copy
- **Non-md-age files:** Pass through unchanged (safe for regular markdown)

Files with `age-encrypt: yes` in frontmatter are encrypted; others are untouched.

### Commands

```bash
md-age git init                    # Set up filters in current repo
md-age git config add -i <path>    # Add identity for decryption
md-age git config list             # Show configured identities
md-age git config remove -i <path> # Remove identity
md-age git rekey [files...]        # Re-encrypt after changing recipients
```

### Fresh Clone

After cloning a repo with md-age files:

```bash
cd repo
md-age git config add -i ~/.age/key.txt
git checkout .  # Re-checkout to trigger decryption
```

## Directory Encryption

Encrypt entire directories of arbitrary files (configs, keys, assets).
Each file is individually encrypted in a frontmatter envelope. The working
tree has raw plaintext files; git stores encrypted blobs.

### Setup

1. Set up filters and add your identity (if not already done):

```bash
md-age git init
md-age git config add -i ~/.age/key.txt
```

2. Create a `.age-recipients` file (usually at the repo root):

```bash
cat > .age-recipients << 'EOF'
age1example7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
```

3. Mark directories for encryption:

```bash
md-age git add-dir secrets/
md-age git add-dir credentials/
```

This creates a `.age-encrypt` marker and configures `.gitattributes`.

4. Use normally:

```bash
echo '{"api_key": "abc123"}' > secrets/config.json
git add .age-recipients .gitattributes secrets/
git commit -m "Add encrypted secrets"
```

### How It Works

- **`.age-encrypt`** — empty marker file; its presence in a directory
  triggers encryption for all files in that directory
- **`.age-recipients`** — lists recipients (one per line, comments with `#`).
  The clean filter walks up from the file's directory to the git root,
  using the nearest `.age-recipients` it finds. One file at the repo root
  covers all encrypted directories; place one in a subdirectory to override.
- **On commit:** `dir-clean` encrypts each file into a frontmatter envelope
- **On checkout:** `dir-smudge` strips the envelope, restoring raw content
- Binary files, text files, any content — all handled transparently

### Recipient Override

```
repo/
├── .age-recipients          ← default for everything
├── secrets/
│   ├── .age-encrypt
│   └── config.json
├── credentials/
│   ├── .age-encrypt
│   ├── .age-recipients      ← different recipients for this dir
│   └── prod.env
```

### Rekey

After changing `.age-recipients`, re-encrypt files with the new recipients:

```bash
md-age git rekey secrets/
```

## License

AGPL-3.0-or-later
