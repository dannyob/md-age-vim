# md-age-vim

Transparent [age](https://age-encryption.org/) encryption for markdown files in Vim/Neovim.

## Features

- Automatic decryption when opening markdown files
- Automatic encryption when saving
- Preserves all YAML frontmatter (not just age fields)
- ASCII-armored output for git-friendliness
- Supports age public keys, SSH keys, and recipient files

## Installation

Using vim-plug:

```vim
Plug 'dob/md-age-vim'
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

## Commands

- `:MdAgeInit` - Insert frontmatter template
- `:MdAgeStatus` - Show encryption status

## License

AGPL-3.0-or-later
