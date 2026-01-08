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
