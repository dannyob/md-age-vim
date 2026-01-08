" mdage.vim - Core functions for md-age-vim
" License: AGPL-3.0-or-later

" Check if lines start with frontmatter delimiters
" Returns: 1 if frontmatter exists, 0 otherwise
function! mdage#HasFrontmatter(lines) abort
  if len(a:lines) < 3
    return 0
  endif
  if a:lines[0] !=# '---'
    return 0
  endif
  " Look for closing ---
  for i in range(1, len(a:lines) - 1)
    if a:lines[i] ==# '---'
      return 1
    endif
  endfor
  return 0
endfunction

function! mdage#Init() abort
  echo 'md-age: MdAgeInit not yet implemented'
endfunction

function! mdage#Status() abort
  echo 'md-age: MdAgeStatus not yet implemented'
endfunction
