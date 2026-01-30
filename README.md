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
let g:md_age_default_recipients = 'age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p'

" Multiple recipients
let g:md_age_default_recipients = [
  \ 'age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p',
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
  - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
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
```

### Fresh Clone

After cloning a repo with md-age files:

```bash
cd repo
md-age git config add -i ~/.age/key.txt
git checkout .  # Re-checkout to trigger decryption
```

## License

AGPL-3.0-or-later
