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

" Parse frontmatter and return dict with fields and end_line
" Returns: {'fields': {...}, 'end_line': N} or {'fields': {}, 'end_line': -1}
function! mdage#ParseFrontmatter(lines) abort
  let result = {'fields': {}, 'end_line': -1}
  if !mdage#HasFrontmatter(a:lines)
    return result
  endif
  for i in range(1, len(a:lines) - 1)
    let line = a:lines[i]
    if line ==# '---'
      let result.end_line = i
      break
    endif
    " Simple key: value parsing (not full YAML)
    let match = matchlist(line, '^\([^:]\+\):\s*\(.*\)$')
    if len(match) >= 3
      let result.fields[match[1]] = match[2]
    endif
  endfor
  return result
endfunction

" Extract recipients array from frontmatter
" Returns: list of recipient strings
function! mdage#GetRecipients(parsed, lines) abort
  let recipients = []
  " Find age-recipients: line
  let in_recipients = 0
  for i in range(1, a:parsed.end_line - 1)
    let line = a:lines[i]
    if line =~# '^age-recipients:\s*$'
      let in_recipients = 1
      continue
    endif
    if in_recipients
      " Check if this is an array item (starts with whitespace and -)
      let match = matchlist(line, '^\s\+- \(.*\)$')
      if len(match) >= 2
        call add(recipients, match[1])
      elseif line !~# '^\s'
        " No longer indented, end of array
        break
      endif
    endif
  endfor
  return recipients
endfunction

" Build CLI args for recipients
" age1... and ssh-... use -r, file paths use -R
" Returns: string of CLI args
function! mdage#BuildRecipientArgs(recipients) abort
  let args = []
  for r in a:recipients
    if r =~# '^age1' || r =~# '^ssh-'
      " Escape spaces for shell
      let escaped = substitute(r, ' ', '\\ ', 'g')
      call add(args, '-r ' . escaped)
    else
      " File path - use -R
      call add(args, '-R ' . r)
    endif
  endfor
  return join(args, ' ')
endfunction

" Encrypt plaintext using age
" Returns: {'success': 0/1, 'ciphertext': '...', 'error': '...'}
function! mdage#Encrypt(plaintext, recipients) abort
  let result = {'success': 0, 'ciphertext': '', 'error': ''}

  if empty(a:recipients)
    let result.error = 'md-age: no recipients provided'
    return result
  endif

  let cmd = get(g:, 'md_age_command', 'age')
  let recipient_args = mdage#BuildRecipientArgs(a:recipients)

  " Use temp file to avoid shell escaping issues
  let tmpfile = tempname()
  call writefile(split(a:plaintext, "\n", 1), tmpfile, 'b')

  let full_cmd = cmd . ' -e -a ' . recipient_args . ' < ' . shellescape(tmpfile) . ' 2>&1'
  let output = system(full_cmd)
  call delete(tmpfile)

  if v:shell_error
    let result.error = 'md-age: encryption failed: ' . output
    return result
  endif

  let result.success = 1
  let result.ciphertext = trim(output)
  return result
endfunction

function! mdage#Init() abort
  echo 'md-age: MdAgeInit not yet implemented'
endfunction

function! mdage#Status() abort
  echo 'md-age: MdAgeStatus not yet implemented'
endfunction
