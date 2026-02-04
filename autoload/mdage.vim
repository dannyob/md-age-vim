" mdage.vim - Core functions for md-age-vim
" License: AGPL-3.0-or-later

" Normalize a YAML value by stripping quotes and whitespace
" Handles: 'yes', "yes", yes, ' yes ', etc.
function! mdage#NormalizeYamlValue(value) abort
  let v = trim(a:value)
  " Strip single or double quotes
  if (v =~# "^'.*'$") || (v =~# '^".*"$')
    let v = v[1:-2]
  endif
  return trim(v)
endfunction

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
      " Check if this is an array item
      " Accept: '- item', '  - item', '-item' (no space after dash)
      let match = matchlist(line, '^\s*-\s*\(.\+\)$')
      if len(match) >= 2
        call add(recipients, match[1])
      elseif line =~# '^\s*$'
        " Blank line, continue
        continue
      elseif line !~# '^\s'
        " Non-indented non-array line, end of array
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

" Decrypt ciphertext using age
" identity_args: CLI args for identity (e.g., '-i ~/.age/key.txt')
" Returns: {'success': 0/1, 'plaintext': '...', 'error': '...'}
function! mdage#Decrypt(ciphertext, identity_args) abort
  let result = {'success': 0, 'plaintext': '', 'error': ''}

  if empty(a:identity_args)
    let result.error = 'md-age: g:md_age_identity not set'
    return result
  endif

  let cmd = get(g:, 'md_age_command', 'age')

  " Use temp file to avoid shell escaping issues
  let tmpfile = tempname()
  call writefile(split(a:ciphertext, "\n", 1), tmpfile, 'b')

  let full_cmd = cmd . ' -d ' . a:identity_args . ' < ' . shellescape(tmpfile) . ' 2>&1'
  let output = system(full_cmd)
  call delete(tmpfile)

  if v:shell_error
    let result.error = 'md-age: decryption failed'
    return result
  endif

  let result.success = 1
  let result.plaintext = output
  return result
endfunction

" Check if file should be encrypted based on frontmatter
" Returns: 1 if should encrypt, 0 otherwise
function! mdage#ShouldEncrypt(parsed) abort
  if a:parsed.end_line < 0
    return 0
  endif
  let raw_value = get(a:parsed.fields, 'age-encrypt', '')
  let value = mdage#NormalizeYamlValue(raw_value)
  " Accept 'yes' or 'true' (YAML 1.1 boolean literals)
  return value ==# 'yes' || value ==# 'true'
endfunction

" Called on BufReadPost - decrypt if needed
function! mdage#OnBufRead() abort
  let lines = getline(1, '$')
  let parsed = mdage#ParseFrontmatter(lines)

  if !mdage#ShouldEncrypt(parsed)
    return
  endif

  " Check for identity
  if !exists('g:md_age_identity') || empty(g:md_age_identity)
    echoerr 'md-age: g:md_age_identity not set'
    setlocal readonly
    return
  endif

  " Check if body looks encrypted
  let body_start = parsed.end_line + 1
  if body_start >= len(lines)
    " Empty body, nothing to decrypt
    let b:md_age_encrypted = 1
    return
  endif

  " Get the body (everything after frontmatter)
  let body_lines = lines[body_start:]
  let body = join(body_lines, "\n")

  " Strip leading whitespace for check (handles blank lines after frontmatter)
  " Note: [\n\t ]* matches newlines, tabs, and spaces
  let trimmed_body = substitute(body, '^[\n\t ]*', '', '')

  " Check if it looks like armored age output
  if trimmed_body !~# '^-----BEGIN AGE ENCRYPTED FILE-----'
    " Not encrypted - but check for mixed content (corruption)
    if body =~# '-----BEGIN AGE ENCRYPTED FILE-----'
      " Mixed content: plaintext followed by encrypted block
      echoerr 'md-age: WARNING: mixed plaintext and encrypted content detected'
    endif
    " Mark for encryption on save
    let b:md_age_encrypted = 1
    return
  endif

  " Decrypt (use trimmed_body which has leading whitespace removed)
  let result = mdage#Decrypt(trimmed_body, g:md_age_identity)

  if !result.success
    echoerr result.error
    echoerr 'md-age: decryption failed - buffer set read-only'
    setlocal readonly
    return
  endif

  " Replace body with plaintext
  " Keep frontmatter lines (0 to end_line inclusive)
  let new_lines = lines[0:parsed.end_line] + split(result.plaintext, "\n", 1)

  " Update buffer
  setlocal modifiable
  silent! %delete _
  call setline(1, new_lines)
  setlocal nomodified

  let b:md_age_encrypted = 1
endfunction

" Called on BufWritePre - encrypt if needed
function! mdage#OnBufWritePre() abort
  if !get(b:, 'md_age_encrypted', 0)
    let lines = getline(1, '$')
    let parsed = mdage#ParseFrontmatter(lines)
    if !mdage#ShouldEncrypt(parsed)
      return
    endif
  endif

  let lines = getline(1, '$')
  let parsed = mdage#ParseFrontmatter(lines)

  " Get recipients
  let recipients = mdage#GetRecipients(parsed, lines)
  if empty(recipients)
    echoerr 'md-age: no recipients in frontmatter'
    throw 'md-age: save aborted'
  endif

  " Get body (everything after frontmatter)
  let body_start = parsed.end_line + 1
  if body_start >= len(lines)
    let body = ''
  else
    let body = join(lines[body_start:], "\n")
  endif

  " Store plaintext for restoration after write
  let b:md_age_plaintext = body
  let b:md_age_frontmatter_end = parsed.end_line

  " Encrypt
  let result = mdage#Encrypt(body, recipients)
  if !result.success
    echoerr result.error
    throw 'md-age: save aborted'
  endif

  " Replace buffer with frontmatter + ciphertext
  let new_lines = lines[0:parsed.end_line] + split(result.ciphertext, "\n", 1)

  silent! %delete _
  call setline(1, new_lines)
endfunction

" Called on BufWritePost - restore plaintext after save
function! mdage#OnBufWritePost() abort
  if !exists('b:md_age_plaintext')
    return
  endif

  let lines = getline(1, '$')

  " Restore plaintext body
  let new_lines = lines[0:b:md_age_frontmatter_end] + split(b:md_age_plaintext, "\n", 1)

  silent! %delete _
  call setline(1, new_lines)
  setlocal nomodified

  unlet b:md_age_plaintext
  unlet b:md_age_frontmatter_end
endfunction

" Insert frontmatter template at top of buffer
function! mdage#Init() abort
  if mdage#HasFrontmatter(getline(1, '$'))
    echo 'md-age: frontmatter already exists'
    return
  endif

  let template = [
    \ '---',
    \ 'age-encrypt: yes',
    \ 'age-recipients:',
  \ ]

  " Add default recipients if configured, otherwise empty placeholder
  if exists('g:md_age_default_recipients')
    let recipients = g:md_age_default_recipients
    " Handle both string and list
    if type(recipients) == v:t_string
      let recipients = [recipients]
    endif
    for r in recipients
      call add(template, '  - ' . r)
    endfor
  else
    call add(template, '  - ')
  endif

  call add(template, '---')
  call add(template, '')

  call append(0, template)

  " Position cursor: if no defaults, on the empty recipient line; otherwise after frontmatter
  if !exists('g:md_age_default_recipients')
    call cursor(4, 5)
  else
    call cursor(len(template) + 1, 1)
  endif
endfunction

" Show current encryption status
function! mdage#Status() abort
  let lines = getline(1, '$')
  let parsed = mdage#ParseFrontmatter(lines)

  if !mdage#ShouldEncrypt(parsed)
    echo 'md-age: not an encrypted file'
    return
  endif

  if get(b:, 'md_age_encrypted', 0)
    echo 'md-age: decrypted (will encrypt on save)'
    let recipients = mdage#GetRecipients(parsed, lines)
    echo 'md-age: recipients: ' . string(recipients)
  else
    echo 'md-age: encrypted file (not yet decrypted)'
  endif
endfunction
