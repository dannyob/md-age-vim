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
