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
