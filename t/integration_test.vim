" Integration tests for full encrypt/decrypt cycle

function! s:SetupTestKeys()
  " Generate fresh test keys with unique names
  let s:keyfile = tempname() . '-age-key.txt'
  let s:recipientfile = tempname() . '-age-recipient.txt'
  call system('age-keygen -o ' . shellescape(s:keyfile) . ' 2>' . shellescape(s:recipientfile))
  let g:md_age_identity = '-i ' . s:keyfile
  let line = trim(readfile(s:recipientfile)[0])
  let g:test_recipient = substitute(line, '^Public key: ', '', '')
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

function! s:TestDecryptsWithLeadingBlankLine()
  call s:SetupTestKeys()

  " Create test content with plaintext
  let frontmatter = ['---', 'age-encrypt: yes', 'age-recipients:', '  - ' . g:test_recipient, '---']
  let body = ['# Secret Notes', '', 'This is confidential.']
  let content = frontmatter + body

  " Write to temp file
  let tmpfile = tempname() . '.md'
  call writefile(content, tmpfile)

  " Open and save to encrypt
  execute 'edit ' . tmpfile
  write
  bdelete!

  " Read encrypted file - add a blank line after frontmatter
  " (This simulates what git smudge might produce with odd formatting)
  let encrypted = readfile(tmpfile)
  " Insert blank line after frontmatter (line 5 is '---')
  call insert(encrypted, '', 5)
  call writefile(encrypted, tmpfile)

  " Re-open - should still decrypt properly
  execute 'edit ' . tmpfile

  " Body should be decrypted, not raw ciphertext
  " After decryption: line 6 = '# Secret Notes', line 7 = '' (empty from body)
  let line6 = getline(6)
  call testify#assert#equals(line6, '# Secret Notes')
  call testify#assert#not_matches(getline(7), '-----BEGIN AGE')

  bdelete!
  call delete(tmpfile)
endfunction
call testify#it('decrypts with leading blank line after frontmatter', function('s:TestDecryptsWithLeadingBlankLine'))

function! s:TestDetectsMixedContent()
  call s:SetupTestKeys()

  " Create a file with mixed plaintext and ciphertext (corruption)
  let content = [
    \ '---',
    \ 'age-encrypt: yes',
    \ 'age-recipients:',
    \ '  - ' . g:test_recipient,
    \ '---',
    \ 'This is plaintext',
    \ '-----BEGIN AGE ENCRYPTED FILE-----',
    \ 'fake encrypted content',
    \ '-----END AGE ENCRYPTED FILE-----'
  \ ]

  let tmpfile = tempname() . '.md'
  call writefile(content, tmpfile)

  " Open file - should detect mixed content as corruption
  " The echoerr will emit a warning but not crash
  " Use redir to capture the error message
  redir => errmsg
  silent! execute 'edit ' . tmpfile
  redir END

  " Check the warning was emitted
  call testify#assert#matches(errmsg, 'mixed plaintext and encrypted content')

  " Check buffer contains the mixed content (passed through)
  let line6 = getline(6)
  call testify#assert#equals(line6, 'This is plaintext')

  bdelete!
  call delete(tmpfile)
endfunction
call testify#it('handles mixed content gracefully', function('s:TestDetectsMixedContent'))

function! s:TestEncryptOnSaveDisabled()
  call s:SetupTestKeys()

  " Create test content
  let frontmatter = ['---', 'age-encrypt: yes', 'age-recipients:', '  - ' . g:test_recipient, '---']
  let body = ['# Secret Notes', '', 'This is confidential.']
  let content = frontmatter + body

  " Write to temp file
  let tmpfile = tempname() . '.md'
  call writefile(content, tmpfile)

  " Open file
  execute 'edit ' . tmpfile

  " Disable encryption on save
  let b:md_age_encrypt_on_save = 0

  " Save file (should NOT encrypt because we disabled it)
  write

  " Check file on disk is NOT encrypted
  let disk_content = join(readfile(tmpfile), "\n")
  call testify#assert#equals(disk_content =~# 'BEGIN AGE ENCRYPTED FILE', 0)
  call testify#assert#equals(disk_content =~# '# Secret Notes', 1)

  " Re-enable and save again
  let b:md_age_encrypt_on_save = 1
  write

  " Now it should be encrypted
  let disk_content2 = join(readfile(tmpfile), "\n")
  call testify#assert#equals(disk_content2 =~# 'BEGIN AGE ENCRYPTED FILE', 1)

  bdelete!
  call delete(tmpfile)
endfunction
call testify#it('respects b:md_age_encrypt_on_save', function('s:TestEncryptOnSaveDisabled'))

function! s:TestToggleEncryptOnSave()
  " Test the toggle function
  unlet! b:md_age_encrypt_on_save

  " Default should be 1, toggle to 0
  call mdage#ToggleEncryptOnSave()
  call testify#assert#equals(b:md_age_encrypt_on_save, 0)

  " Toggle back to 1
  call mdage#ToggleEncryptOnSave()
  call testify#assert#equals(b:md_age_encrypt_on_save, 1)
endfunction
call testify#it('toggles b:md_age_encrypt_on_save', function('s:TestToggleEncryptOnSave'))
