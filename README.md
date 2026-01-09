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

## Commands

- `:MdAgeInit` - Insert frontmatter template
- `:MdAgeStatus` - Show encryption status

## License

AGPL-3.0-or-later
