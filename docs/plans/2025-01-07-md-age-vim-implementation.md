# md-age-vim Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a vim plugin that transparently encrypts/decrypts markdown files using age, triggered by frontmatter fields.

**Architecture:** Pure vimscript plugin using autoload pattern. Hooks into BufReadPost/BufWritePre/BufWritePost for `*.md` files. Parses YAML frontmatter to detect encryption settings, shells out to age for actual crypto.

**Tech Stack:** Vimscript, age CLI, vim-testify for TDD

---

## Prerequisites

Before starting, ensure:
- `age` is installed (`brew install age` or equivalent)
- vim-testify is installed in nvim
- Generate a test keypair:
  ```bash
  age-keygen -o /tmp/test-age-key.txt 2>/tmp/test-age-recipient.txt
  ```

---

### Task 1: Project Structure

**Files:**
- Create: `plugin/md-age.vim`
- Create: `autoload/mdage.vim`
- Create: `t/frontmatter_test.vim`

**Step 1: Create plugin skeleton**

Create `plugin/md-age.vim`:
```vim
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
```

**Step 2: Create autoload skeleton**

Create `autoload/mdage.vim`:
```vim
" mdage.vim - Core functions for md-age-vim
" License: AGPL-3.0-or-later

function! mdage#Init() abort
  echo 'md-age: MdAgeInit not yet implemented'
endfunction

function! mdage#Status() abort
  echo 'md-age: MdAgeStatus not yet implemented'
endfunction
```

**Step 3: Create test directory and first test file**

Create `t/frontmatter_test.vim`:
```vim
" Tests for frontmatter parsing

function! s:TestPluginLoads()
  call testify#assert#equals(exists('g:loaded_md_age'), 0)
endfunction
call testify#it('plugin not loaded in test context', function('s:TestPluginLoads'))
```

**Step 4: Run tests to verify setup**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: Test passes (plugin shouldn't be loaded in test context)

**Step 5: Commit**

```bash
git add plugin/md-age.vim autoload/mdage.vim t/frontmatter_test.vim
git commit -m "feat: add project skeleton with plugin/autoload structure"
```

---

### Task 2: Frontmatter Detection

**Files:**
- Modify: `autoload/mdage.vim`
- Modify: `t/frontmatter_test.vim`

**Step 1: Write failing test for frontmatter detection**

Add to `t/frontmatter_test.vim`:
```vim
function! s:TestHasFrontmatter()
  let lines = ['---', 'title: Test', '---', 'body']
  call testify#assert#equals(mdage#HasFrontmatter(lines), 1)
endfunction
call testify#it('detects frontmatter', function('s:TestHasFrontmatter'))

function! s:TestNoFrontmatter()
  let lines = ['# Just a heading', 'body']
  call testify#assert#equals(mdage#HasFrontmatter(lines), 0)
endfunction
call testify#it('detects missing frontmatter', function('s:TestNoFrontmatter'))

function! s:TestEmptyFile()
  let lines = []
  call testify#assert#equals(mdage#HasFrontmatter(lines), 0)
endfunction
call testify#it('handles empty file', function('s:TestEmptyFile'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#HasFrontmatter"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/frontmatter_test.vim
git commit -m "feat: add frontmatter detection"
```

---

### Task 3: Frontmatter Parsing

**Files:**
- Modify: `autoload/mdage.vim`
- Modify: `t/frontmatter_test.vim`

**Step 1: Write failing test for frontmatter parsing**

Add to `t/frontmatter_test.vim`:
```vim
function! s:TestParseFrontmatter()
  let lines = ['---', 'title: Test', 'age-encrypt: yes', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  call testify#assert#equals(result.end_line, 3)
  call testify#assert#equals(result.fields['age-encrypt'], 'yes')
  call testify#assert#equals(result.fields['title'], 'Test')
endfunction
call testify#it('parses frontmatter fields', function('s:TestParseFrontmatter'))

function! s:TestParseFrontmatterPreservesAll()
  let lines = ['---', 'title: My Doc', 'date: 2025-01-07', 'age-encrypt: yes', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  call testify#assert#equals(len(result.fields), 3)
endfunction
call testify#it('preserves all frontmatter fields', function('s:TestParseFrontmatterPreservesAll'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#ParseFrontmatter"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/frontmatter_test.vim
git commit -m "feat: add frontmatter parsing"
```

---

### Task 4: Parse Recipients Array

**Files:**
- Modify: `autoload/mdage.vim`
- Create: `t/recipients_test.vim`

**Step 1: Write failing test for recipient array parsing**

Create `t/recipients_test.vim`:
```vim
" Tests for recipient parsing

function! s:TestParseRecipientsArray()
  let lines = ['---', 'age-encrypt: yes', 'age-recipients:', '  - age1abc123', '  - age1def456', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  let recipients = mdage#GetRecipients(result, lines)
  call testify#assert#equals(len(recipients), 2)
  call testify#assert#equals(recipients[0], 'age1abc123')
  call testify#assert#equals(recipients[1], 'age1def456')
endfunction
call testify#it('parses recipient array', function('s:TestParseRecipientsArray'))

function! s:TestParseRecipientsWithFilePath()
  let lines = ['---', 'age-recipients:', '  - ~/.age/keys.txt', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  let recipients = mdage#GetRecipients(result, lines)
  call testify#assert#equals(recipients[0], '~/.age/keys.txt')
endfunction
call testify#it('parses file path recipient', function('s:TestParseRecipientsWithFilePath'))

function! s:TestParseRecipientsSSH()
  let lines = ['---', 'age-recipients:', '  - ssh-ed25519 AAAA...', '---', 'body']
  let result = mdage#ParseFrontmatter(lines)
  let recipients = mdage#GetRecipients(result, lines)
  call testify#assert#equals(recipients[0], 'ssh-ed25519 AAAA...')
endfunction
call testify#it('parses SSH key recipient', function('s:TestParseRecipientsSSH'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/recipients_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#GetRecipients"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/recipients_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/recipients_test.vim
git commit -m "feat: add recipient array parsing from frontmatter"
```

---

### Task 5: Build Recipient CLI Args

**Files:**
- Modify: `autoload/mdage.vim`
- Modify: `t/recipients_test.vim`

**Step 1: Write failing test for recipient arg building**

Add to `t/recipients_test.vim`:
```vim
function! s:TestBuildRecipientArgsPublicKey()
  let recipients = ['age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p']
  let args = mdage#BuildRecipientArgs(recipients)
  call testify#assert#equals(args, '-r age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p')
endfunction
call testify#it('builds -r arg for age public key', function('s:TestBuildRecipientArgsPublicKey'))

function! s:TestBuildRecipientArgsSSH()
  let recipients = ['ssh-ed25519 AAAAC3NzaC1lZDI1NTE5']
  let args = mdage#BuildRecipientArgs(recipients)
  call testify#assert#equals(args, '-r ssh-ed25519\ AAAAC3NzaC1lZDI1NTE5')
endfunction
call testify#it('builds -r arg for SSH key', function('s:TestBuildRecipientArgsSSH'))

function! s:TestBuildRecipientArgsFile()
  let recipients = ['~/.age/recipients.txt']
  let args = mdage#BuildRecipientArgs(recipients)
  call testify#assert#equals(args, '-R ~/.age/recipients.txt')
endfunction
call testify#it('builds -R arg for file path', function('s:TestBuildRecipientArgsFile'))

function! s:TestBuildRecipientArgsMultiple()
  let recipients = ['age1abc', '~/.age/keys.txt']
  let args = mdage#BuildRecipientArgs(recipients)
  call testify#assert#equals(args, '-r age1abc -R ~/.age/keys.txt')
endfunction
call testify#it('builds multiple recipient args', function('s:TestBuildRecipientArgsMultiple'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/recipients_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#BuildRecipientArgs"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/recipients_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/recipients_test.vim
git commit -m "feat: build recipient CLI args with -r/-R flags"
```

---

### Task 6: Encrypt Function

**Files:**
- Modify: `autoload/mdage.vim`
- Create: `t/encrypt_test.vim`

**Step 1: Write failing test for encryption**

Create `t/encrypt_test.vim`:
```vim
" Tests for encryption/decryption
" Requires: age installed, test key at /tmp/test-age-key.txt

function! s:TestEncryptProducesArmoredOutput()
  " Read recipient from test key
  let recipient = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let plaintext = "Hello, World!"
  let result = mdage#Encrypt(plaintext, [recipient])
  call testify#assert#equals(result.success, 1)
  call testify#assert#equals(result.ciphertext =~# '^-----BEGIN AGE ENCRYPTED FILE-----', 1)
  call testify#assert#equals(result.ciphertext =~# '-----END AGE ENCRYPTED FILE-----$', 1)
endfunction
call testify#it('encrypts to armored output', function('s:TestEncryptProducesArmoredOutput'))

function! s:TestEncryptFailsWithNoRecipients()
  let plaintext = "Hello, World!"
  let result = mdage#Encrypt(plaintext, [])
  call testify#assert#equals(result.success, 0)
endfunction
call testify#it('fails with no recipients', function('s:TestEncryptFailsWithNoRecipients'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/encrypt_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#Encrypt"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/encrypt_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/encrypt_test.vim
git commit -m "feat: add encryption function"
```

---

### Task 7: Decrypt Function

**Files:**
- Modify: `autoload/mdage.vim`
- Modify: `t/encrypt_test.vim`

**Step 1: Write failing test for decryption**

Add to `t/encrypt_test.vim`:
```vim
function! s:TestDecryptRoundtrip()
  let recipient = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let identity = '-i /tmp/test-age-key.txt'
  let plaintext = "Secret message\nWith multiple lines"

  let encrypted = mdage#Encrypt(plaintext, [recipient])
  call testify#assert#equals(encrypted.success, 1)

  let decrypted = mdage#Decrypt(encrypted.ciphertext, identity)
  call testify#assert#equals(decrypted.success, 1)
  call testify#assert#equals(decrypted.plaintext, plaintext)
endfunction
call testify#it('roundtrip encrypt/decrypt', function('s:TestDecryptRoundtrip'))

function! s:TestDecryptFailsWithWrongKey()
  " Create a different keypair
  call system('age-keygen -o /tmp/test-age-wrong-key.txt 2>/dev/null')

  let recipient = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let encrypted = mdage#Encrypt("test", [recipient])

  let decrypted = mdage#Decrypt(encrypted.ciphertext, '-i /tmp/test-age-wrong-key.txt')
  call testify#assert#equals(decrypted.success, 0)
endfunction
call testify#it('fails with wrong key', function('s:TestDecryptFailsWithWrongKey'))

function! s:TestDecryptFailsWithNoIdentity()
  let recipient = trim(readfile('/tmp/test-age-recipient.txt')[0])
  let encrypted = mdage#Encrypt("test", [recipient])

  let decrypted = mdage#Decrypt(encrypted.ciphertext, '')
  call testify#assert#equals(decrypted.success, 0)
endfunction
call testify#it('fails with no identity', function('s:TestDecryptFailsWithNoIdentity'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/encrypt_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#Decrypt"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/encrypt_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/encrypt_test.vim
git commit -m "feat: add decryption function"
```

---

### Task 8: ShouldEncrypt Check

**Files:**
- Modify: `autoload/mdage.vim`
- Modify: `t/frontmatter_test.vim`

**Step 1: Write failing test for ShouldEncrypt**

Add to `t/frontmatter_test.vim`:
```vim
function! s:TestShouldEncryptYes()
  let parsed = {'fields': {'age-encrypt': 'yes'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 1)
endfunction
call testify#it('should encrypt when age-encrypt: yes', function('s:TestShouldEncryptYes'))

function! s:TestShouldEncryptNo()
  let parsed = {'fields': {'age-encrypt': 'no'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt when age-encrypt: no', function('s:TestShouldEncryptNo'))

function! s:TestShouldEncryptMissing()
  let parsed = {'fields': {'title': 'Test'}, 'end_line': 2}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt when age-encrypt missing', function('s:TestShouldEncryptMissing'))

function! s:TestShouldEncryptNoFrontmatter()
  let parsed = {'fields': {}, 'end_line': -1}
  call testify#assert#equals(mdage#ShouldEncrypt(parsed), 0)
endfunction
call testify#it('should not encrypt with no frontmatter', function('s:TestShouldEncryptNoFrontmatter'))
```

**Step 2: Run test to verify it fails**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: FAIL with "Unknown function: mdage#ShouldEncrypt"

**Step 3: Write minimal implementation**

Add to `autoload/mdage.vim`:
```vim
" Check if file should be encrypted based on frontmatter
" Returns: 1 if should encrypt, 0 otherwise
function! mdage#ShouldEncrypt(parsed) abort
  if a:parsed.end_line < 0
    return 0
  endif
  return get(a:parsed.fields, 'age-encrypt', '') ==# 'yes'
endfunction
```

**Step 4: Run test to verify it passes**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source autoload/mdage.vim' -c 'source t/frontmatter_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add autoload/mdage.vim t/frontmatter_test.vim
git commit -m "feat: add ShouldEncrypt check"
```

---

### Task 9: BufReadPost Handler (Decrypt on Load)

**Files:**
- Modify: `plugin/md-age.vim`
- Modify: `autoload/mdage.vim`

**Step 1: Add autocommand to plugin file**

Update `plugin/md-age.vim` to add:
```vim
" Autocommands for transparent encryption
augroup md_age
  autocmd!
  autocmd BufReadPost *.md call mdage#OnBufRead()
  autocmd BufWritePre *.md call mdage#OnBufWritePre()
  autocmd BufWritePost *.md call mdage#OnBufWritePost()
augroup END
```

**Step 2: Add OnBufRead handler**

Add to `autoload/mdage.vim`:
```vim
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

  " Check if it looks like armored age output
  if body !~# '^-----BEGIN AGE ENCRYPTED FILE-----'
    " Not encrypted yet, just mark for encryption on save
    let b:md_age_encrypted = 1
    return
  endif

  " Decrypt
  let result = mdage#Decrypt(body, g:md_age_identity)

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
```

**Step 3: Test manually**

Create test file `/tmp/test-encrypted.md`:
```markdown
---
age-encrypt: yes
age-recipients:
  - <paste recipient from /tmp/test-age-recipient.txt>
---
This is secret content.
```

Set identity: `let g:md_age_identity = '-i /tmp/test-age-key.txt'`

Encrypt the body manually:
```bash
echo "This is secret content." | age -e -a -r <recipient> > /tmp/body.age
```

Replace body in test file with encrypted content, then open in vim.

Expected: File opens with decrypted content visible.

**Step 4: Commit**

```bash
git add plugin/md-age.vim autoload/mdage.vim
git commit -m "feat: add BufReadPost handler for decryption on load"
```

---

### Task 10: BufWritePre Handler (Encrypt on Save)

**Files:**
- Modify: `autoload/mdage.vim`

**Step 1: Add OnBufWritePre handler**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 2: Add OnBufWritePost handler**

Add to `autoload/mdage.vim`:
```vim
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
```

**Step 3: Test manually**

1. Open a new file `test.md`
2. Add frontmatter with `age-encrypt: yes` and valid recipient
3. Add some body content
4. Save (`:w`)
5. Check the file on disk shows encrypted content
6. Buffer should still show plaintext
7. Close and reopen - should decrypt automatically

**Step 4: Commit**

```bash
git add autoload/mdage.vim
git commit -m "feat: add BufWritePre/Post handlers for encryption on save"
```

---

### Task 11: MdAgeInit Command

**Files:**
- Modify: `autoload/mdage.vim`

**Step 1: Implement MdAgeInit**

Update `mdage#Init()` in `autoload/mdage.vim`:
```vim
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
    \ '  - ',
    \ '---',
    \ ''
  \ ]

  call append(0, template)
  " Position cursor on recipient line
  call cursor(4, 5)
endfunction
```

**Step 2: Test manually**

1. Open new empty file
2. Run `:MdAgeInit`
3. Should insert template with cursor on recipient line

**Step 3: Commit**

```bash
git add autoload/mdage.vim
git commit -m "feat: implement MdAgeInit command"
```

---

### Task 12: MdAgeStatus Command

**Files:**
- Modify: `autoload/mdage.vim`

**Step 1: Implement MdAgeStatus**

Update `mdage#Status()` in `autoload/mdage.vim`:
```vim
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
```

**Step 2: Test manually**

1. Open encrypted file
2. Run `:MdAgeStatus`
3. Should show status and recipients

**Step 3: Commit**

```bash
git add autoload/mdage.vim
git commit -m "feat: implement MdAgeStatus command"
```

---

### Task 13: Help Documentation

**Files:**
- Create: `doc/md-age.txt`

**Step 1: Create help file**

Create `doc/md-age.txt`:
```
*md-age.txt*  Transparent age encryption for markdown files

Author:  Danny O'Brien <danny@spesh.com>
License: AGPL-3.0-or-later

INTRODUCTION                                    *md-age*

md-age-vim provides transparent encryption and decryption of markdown files
using age (https://age-encryption.org/). Files are automatically decrypted
when opened and encrypted when saved, based on YAML frontmatter configuration.

CONFIGURATION                                   *md-age-config*

                                                *g:md_age_identity*
g:md_age_identity~
    Required. Command-line arguments for age identity.
    Examples: >
        let g:md_age_identity = '-i ~/.age/identity.txt'
        let g:md_age_identity = '-j'  " for age plugins
<
                                                *g:md_age_command*
g:md_age_command~
    Optional. The age command to use. Default: 'age'
    Example: >
        let g:md_age_command = 'rage'
<
FRONTMATTER FORMAT                              *md-age-frontmatter*

Enable encryption by adding these fields to YAML frontmatter: >

    ---
    title: My Document
    age-encrypt: yes
    age-recipients:
      - age1ql3z7hjy54pw...
      - ~/.age/recipients.txt
      - ssh-ed25519 AAAA...
    ---
<
Recipients can be:
- age public keys (starting with 'age1')
- SSH public keys (starting with 'ssh-')
- Paths to recipient files (anything else, uses -R flag)

COMMANDS                                        *md-age-commands*

                                                *:MdAgeInit*
:MdAgeInit          Insert frontmatter template at top of buffer.

                                                *:MdAgeStatus*
:MdAgeStatus        Show current encryption status and recipients.

ERROR HANDLING                                  *md-age-errors*

If decryption fails (wrong key, corrupted file):
- Buffer is set to read-only
- Encrypted content remains visible
- Error message is displayed

If encryption fails:
- Save is aborted
- Error message is displayed

 vim:tw=78:ts=8:ft=help:norl:
```

**Step 2: Generate help tags**

Run: `vim -c 'helptags doc/' -c 'q'`

**Step 3: Commit**

```bash
git add doc/md-age.txt
git commit -m "docs: add vim help documentation"
```

---

### Task 14: Final Integration Test

**Files:**
- Create: `t/integration_test.vim`

**Step 1: Create integration test**

Create `t/integration_test.vim`:
```vim
" Integration tests for full encrypt/decrypt cycle

function! s:SetupTestKeys()
  " Generate fresh test keys
  call system('age-keygen -o /tmp/test-age-key.txt 2>/tmp/test-age-recipient.txt')
  let g:md_age_identity = '-i /tmp/test-age-key.txt'
  let g:test_recipient = trim(readfile('/tmp/test-age-recipient.txt')[0])
endfunction

function! s:TestFullCycle()
  call s:SetupTestKeys()

  " Create test content
  let frontmatter = ['---', 'age-encrypt: yes', 'age-recipients:', '  - ' . g:test_recipient, '---']
  let body = ['# Secret Notes', '', 'This is confidential.']
  let content = frontmatter + body

  " Write to temp file
  let tmpfile = tempname() . '.md'
  call writefile(content, tmpfile)

  " Open file (should not encrypt since not already encrypted)
  execute 'edit ' . tmpfile

  " Save file (should encrypt)
  write

  " Check file on disk is encrypted
  let disk_content = join(readfile(tmpfile), "\n")
  call testify#assert#equals(disk_content =~# 'BEGIN AGE ENCRYPTED FILE', 1)

  " Buffer should still show plaintext
  call testify#assert#equals(getline(6), '# Secret Notes')

  " Close and cleanup
  bdelete!
  call delete(tmpfile)
endfunction
call testify#it('full encrypt/decrypt cycle', function('s:TestFullCycle'))
```

**Step 2: Run integration test**

Run: `nvim -u NONE -c 'set rtp+=.' -c 'set rtp+=~/.local/share/nvim/plugged/vim-testify' -c 'source plugin/md-age.vim' -c 'source t/integration_test.vim' -c 'TestifyFile'`

Expected: All tests PASS

**Step 3: Commit**

```bash
git add t/integration_test.vim
git commit -m "test: add integration test for full encrypt/decrypt cycle"
```

---

### Task 15: README

**Files:**
- Create: `README.md`

**Step 1: Create README**

Create `README.md`:
```markdown
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
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Summary

15 tasks covering:
1. Project skeleton
2. Frontmatter detection
3. Frontmatter parsing
4. Recipient array parsing
5. Recipient CLI args building
6. Encrypt function
7. Decrypt function
8. ShouldEncrypt check
9. BufReadPost handler
10. BufWritePre/Post handlers
11. MdAgeInit command
12. MdAgeStatus command
13. Help documentation
14. Integration test
15. README

Each task follows TDD: write failing test → verify failure → implement → verify pass → commit.
