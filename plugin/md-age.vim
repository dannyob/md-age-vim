" md-age.vim - Transparent age encryption for markdown files
" Maintainer: Danny O'Brien <danny@spesh.com>
" License: AGPL-3.0-or-later

if exists('g:loaded_md_age')
  finish
endif
let g:loaded_md_age = 1

" Default command
if !exists('g:md_age_command')
  let g:md_age_command = 'age'
endif

" Commands
command! MdAgeInit call mdage#Init()
command! MdAgeStatus call mdage#Status()

" Autocommands for transparent encryption
augroup md_age
  autocmd!
  autocmd BufReadPost *.md call mdage#OnBufRead()
  autocmd BufWritePre *.md call mdage#OnBufWritePre()
  autocmd BufWritePost *.md call mdage#OnBufWritePost()
augroup END
